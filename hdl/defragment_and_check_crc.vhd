----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz>
--
-- Module Name: defragment_and_check_crc - Behavioral
--
-- Description: Defragment packets into a stream of contiguous bytes and (optionally)
--              drop frames whose IEEE 802.3 CRC32 (FCS) does not check out.
--
--              FCS is the trailing 4 bytes of each Ethernet frame. We run a
--              standard reflected CRC32 (poly 0xEDB88320, init 0xFFFFFFFF) over
--              every received byte INCLUDING the FCS. For a valid frame the
--              final internal CRC equals the constant residue 0xDEBB20E3. On
--              mismatch we roll write_addr back to start_of_packet_addr so the
--              bad frame never becomes visible to the downstream parsers.
--
--              Set check_crc => false to keep the original pass-everything
--              behaviour (useful for testbenches that drive crafted frames).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity defragment_and_check_crc is
    generic (
        check_crc : boolean := true);
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

    signal input_data_present_last  : std_logic := '0';

    signal ram_data_out : std_logic_vector(8 downto 0);

    -- CRC32 state. Updated combinationally per byte; reset on each new packet.
    constant CRC_INIT     : unsigned(31 downto 0) := x"FFFFFFFF";
    constant CRC_RESIDUE  : unsigned(31 downto 0) := x"DEBB20E3";
    signal   crc_state    : unsigned(31 downto 0) := CRC_INIT;

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
    variable v_crc_after_byte   : unsigned(31 downto 0);
    variable crc_ok             : boolean;
    begin
        if rising_edge(clk) then
            -- The decrementing of complete_packets is delayed
            -- one cycle (occurs after the cycle where the data
            -- is read; lets the buffer live in BRAM rather than LUTs).
            if v_complete_packets /= 0 and ram_data_out(8) = '0' then
                v_complete_packets := v_complete_packets - 1;
            else
                v_complete_packets := complete_packets;
            end if;

            if input_data_enable = '1' then
                v_crc_after_byte := crc32_step(crc_state, unsigned(input_data));

                if input_data_present_last = '0' then
                    if input_data_present = '0' then
                        -- two or more idle words in a row
                        NULL;
                    else
                        -- start of packet
                        start_of_packet_addr <= write_addr;
                        data_buffer(to_integer(write_addr)) <= input_data_present & input_data;
                        write_addr <= write_addr + 1;
                        crc_state  <= crc32_step(CRC_INIT, unsigned(input_data));
                    end if;
                else
                    if input_data_present = '1' then
                        -- middle of packet
                        data_buffer(to_integer(write_addr)) <= input_data_present & input_data;
                        write_addr <= write_addr + 1;
                        crc_state  <= v_crc_after_byte;
                    else
                        -- end of packet: the previous byte was the last FCS byte;
                        -- crc_state now reflects the full frame including FCS.
                        if check_crc then
                            crc_ok := (crc_state = CRC_RESIDUE);
                        else
                            crc_ok := true;
                        end if;

                        if crc_ok then
                            -- Skip backwards over the FCS bytes; the downstream parser
                            -- expects frame data only (no trailing CRC).
                            v_complete_packets := v_complete_packets + 1;
                            data_buffer(to_integer(write_addr - 4)) <= input_data_present & input_data;
                            write_addr <= write_addr - 4 + 1;
                        else
                            -- Bad CRC: rewind to start of packet so it never goes out
                            write_addr <= start_of_packet_addr;
                        end if;

                        -- Reset CRC for next packet
                        crc_state <= CRC_INIT;
                    end if;
                end if;

                input_data_present_last <= input_data_present;
            end if;

            -- Streaming out any completed packets
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
