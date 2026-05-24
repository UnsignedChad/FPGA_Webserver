----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz>
--
-- Module Name: defragment_and_check_crc - Behavioral
--
-- Description: Defragment packets into a stream of contiguous bytes; optionally
--              drop frames that fail the Ethernet FCS check or whose destination
--              MAC is neither our_mac nor the broadcast address.
--
-- CRC check: standard reflected CRC32 (poly 0xEDB88320, init 0xFFFFFFFF) over
--            every received byte including the FCS. For a valid frame the
--            internal CRC at end of packet equals the constant residue
--            0xDEBB20E3. Behaviour is gated by check_crc.
--
-- MAC filter: when filter_mac is true, captures the first 6 received bytes (the
--             destination MAC) and at end-of-packet rejects the frame if those
--             bytes match neither our_mac nor FF:FF:FF:FF:FF:FF. our_mac is
--             passed in the project's BYTE-REVERSED storage convention.
--
-- On any rejection (bad CRC or bad MAC), write_addr is rewound to
-- start_of_packet_addr so the frame never becomes visible downstream.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity defragment_and_check_crc is
    generic (
        check_crc  : boolean := true;
        filter_mac : boolean := true;
        our_mac    : std_logic_vector(47 downto 0) := (others => '0'));
    Port (  clk               : in  STD_LOGIC;
            input_data_enable  : in  STD_LOGIC;
            input_data         : in  STD_LOGIC_VECTOR (7 downto 0);
            input_data_present : in  STD_LOGIC;
            input_data_error   : in  STD_LOGIC;
            packet_data_valid  : out STD_LOGIC := '0';
            packet_data        : out STD_LOGIC_VECTOR (7 downto 0) := (others=>'0'));
end defragment_and_check_crc;

architecture Behavioral of defragment_and_check_crc is
    type a_buffer is array(0 to 2047) of std_logic_vector(8 downto 0);
    signal data_buffer : a_buffer := (others => (others => '0'));

    signal read_addr            : unsigned(10 downto 0) := (others => '0');
    signal start_of_packet_addr : unsigned(10 downto 0) := (others => '0');
    signal write_addr           : unsigned(10 downto 0) := (others => '0');
    signal complete_packets     : unsigned(7 downto 0) := (others => '0');

    signal input_data_present_last : std_logic := '0';
    signal ram_data_out            : std_logic_vector(8 downto 0);

    -- our_mac is byte-reversed; rearrange to wire order (byte 0 at MSB) so it
    -- compares directly against captured dst_mac.
    constant our_mac_wire : std_logic_vector(47 downto 0) :=
        our_mac( 7 downto  0) &
        our_mac(15 downto  8) &
        our_mac(23 downto 16) &
        our_mac(31 downto 24) &
        our_mac(39 downto 32) &
        our_mac(47 downto 40);
    constant BROADCAST_MAC : std_logic_vector(47 downto 0) := (others => '1');

    signal dst_mac_capture : std_logic_vector(47 downto 0) := (others => '0');
    signal byte_count      : unsigned(2 downto 0) := (others => '0');

    -- CRC32 state. Updated per byte; reset on each new packet.
    constant CRC_INIT    : unsigned(31 downto 0) := x"FFFFFFFF";
    constant CRC_RESIDUE : unsigned(31 downto 0) := x"DEBB20E3";
    signal   crc_state   : unsigned(31 downto 0) := CRC_INIT;

    function crc32_step(state : unsigned(31 downto 0);
                        b     : unsigned( 7 downto 0)) return unsigned is
        variable c : unsigned(31 downto 0);
    begin
        c := state xor (x"000000" & b);
        for k in 0 to 7 loop
            if c(0) = '1' then
                c := ("0" & c(31 downto 1)) xor x"EDB88320";
            else
                c := "0" & c(31 downto 1);
            end if;
        end loop;
        return c;
    end function;

begin
    packet_data_valid <= ram_data_out(8);
    packet_data       <= ram_data_out(7 downto 0);

process(clk)
    variable v_complete_packets : unsigned(7 downto 0) := (others => '0');
    variable crc_ok             : boolean;
    variable mac_ok             : boolean;
    begin
        if rising_edge(clk) then
            -- delayed decrement of complete_packets (BRAM-friendly)
            if v_complete_packets /= 0 and ram_data_out(8) = '0' then
                v_complete_packets := v_complete_packets - 1;
            else
                v_complete_packets := complete_packets;
            end if;

            if input_data_enable = '1' then
                if input_data_present_last = '0' then
                    if input_data_present = '1' then
                        -- start of packet
                        start_of_packet_addr <= write_addr;
                        data_buffer(to_integer(write_addr)) <= input_data_present & input_data;
                        write_addr      <= write_addr + 1;
                        crc_state       <= crc32_step(CRC_INIT, unsigned(input_data));
                        dst_mac_capture <= dst_mac_capture(39 downto 0) & input_data;
                        byte_count      <= "001";
                    end if;
                else
                    if input_data_present = '1' then
                        -- middle of packet
                        data_buffer(to_integer(write_addr)) <= input_data_present & input_data;
                        write_addr <= write_addr + 1;
                        crc_state  <= crc32_step(crc_state, unsigned(input_data));
                        if byte_count < 6 then
                            dst_mac_capture <= dst_mac_capture(39 downto 0) & input_data;
                            byte_count      <= byte_count + 1;
                        end if;
                    else
                        -- end of packet
                        if check_crc then
                            crc_ok := (crc_state = CRC_RESIDUE);
                        else
                            crc_ok := true;
                        end if;
                        if filter_mac then
                            mac_ok := (dst_mac_capture = our_mac_wire)
                                   or (dst_mac_capture = BROADCAST_MAC);
                        else
                            mac_ok := true;
                        end if;

                        if crc_ok and mac_ok then
                            -- accept: skip back over the 4 FCS bytes
                            v_complete_packets := v_complete_packets + 1;
                            data_buffer(to_integer(write_addr - 4)) <= input_data_present & input_data;
                            write_addr <= write_addr - 4 + 1;
                        else
                            -- reject: rewind
                            write_addr <= start_of_packet_addr;
                        end if;

                        crc_state  <= CRC_INIT;
                        byte_count <= (others => '0');
                    end if;
                end if;
                input_data_present_last <= input_data_present;
            end if;

            -- Streaming out completed packets
            if v_complete_packets /= 0 then
                ram_data_out <= data_buffer(to_integer(read_addr));
                read_addr    <= read_addr + 1;
            else
                ram_data_out <= (others => '0');
            end if;
            complete_packets <= v_complete_packets;
        end if;
    end process;

end Behavioral;
