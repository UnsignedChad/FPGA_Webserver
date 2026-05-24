----------------------------------------------------------------------------------
-- tb_harness - self-checking testbench for main_design
--
-- Scenario 1 (MVP): send a broadcast ARP request asking for our_ip, observe
-- that main_design replies with an ARP reply containing our_mac.
--
-- Frame injection: drives main_design's RX byte interface (preamble + frame).
-- Frame capture:   observes the byte stream feeding the (sim stub) tx_rgmii
--                  via VHDL-2008 external names.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.net_pkg.all;

entity tb_harness is
end tb_harness;

architecture sim of tb_harness is

    -- ---- DUT clocks / control ----
    signal clk125MHz   : std_logic := '0';
    signal clk125MHz90 : std_logic := '0';
    signal phy_ready   : std_logic := '1';
    signal status      : std_logic_vector(3 downto 0);

    -- ---- RX byte interface (testbench -> DUT) ----
    signal input_empty        : std_logic := '1';
    signal input_read         : std_logic;
    signal input_data         : std_logic_vector(7 downto 0) := (others => '0');
    signal input_data_present : std_logic := '0';
    signal input_data_error   : std_logic := '0';

    -- ---- TX PHY pins (driven by sim tx_rgmii; ignored by checker) ----
    signal eth_txck  : std_logic;
    signal eth_txctl : std_logic;
    signal eth_txd   : std_logic_vector(3 downto 0);

    -- NOTE: the design stores MAC/IP/netmask BYTE-REVERSED in these constants
    -- (see "Using the UDP interface.txt"). On-wire octets are reversed.
    constant our_mac     : std_logic_vector(47 downto 0) := x"AB_89_67_45_23_02"; -- 02:23:45:67:89:AB
    constant our_ip      : std_logic_vector(31 downto 0) := x"0A_00_00_0A";       -- 10.0.0.10
    constant our_netmask : std_logic_vector(31 downto 0) := x"00_FF_FF_FF";       -- 255.255.255.0

    -- captured TX frame
    signal rx_frame_buf   : byte_array_t(0 to 1023) := (others => (others => '0'));
    signal rx_frame_len   : integer := 0;
    signal rx_frame_ready : boolean := false;

    -- ---- DUT component ----
    component main_design is
        generic (
            our_mac     : std_logic_vector(47 downto 0) := (others => '0');
            our_netmask : std_logic_vector(31 downto 0) := (others => '0');
            our_ip      : std_logic_vector(31 downto 0) := (others => '0'));
        port (
            clk125Mhz          : in  std_logic;
            clk125Mhz90        : in  std_logic;
            input_empty        : in  std_logic;
            input_read         : out std_logic;
            input_data         : in  std_logic_vector(7 downto 0);
            input_data_present : in  std_logic;
            input_data_error   : in  std_logic;
            phy_ready          : in  std_logic;
            status             : out std_logic_vector(3 downto 0);
            eth_txck           : out std_logic;
            eth_txctl          : out std_logic;
            eth_txd            : out std_logic_vector(3 downto 0));
    end component;

begin

    -- 125 MHz / 8 ns period; clk90 lags by 2 ns
    clk_gen: process
    begin
        clk125Mhz   <= '1';
        wait for 2 ns;
        clk125Mhz90 <= '1';
        wait for 2 ns;
        clk125Mhz   <= '0';
        wait for 2 ns;
        clk125Mhz90 <= '0';
        wait for 2 ns;
    end process;

    i_dut: main_design
        generic map (
            our_mac     => our_mac,
            our_netmask => our_netmask,
            our_ip      => our_ip)
        port map (
            clk125Mhz          => clk125Mhz,
            clk125Mhz90        => clk125Mhz90,
            input_empty        => input_empty,
            input_read         => input_read,
            input_data         => input_data,
            input_data_present => input_data_present,
            input_data_error   => input_data_error,
            phy_ready          => phy_ready,
            status             => status,
            eth_txck           => eth_txck,
            eth_txctl          => eth_txctl,
            eth_txd            => eth_txd);

    -- ----------------------------------------------------------------
    -- TX snoop: capture bytes flowing into tx_rgmii_sim via external name.
    -- A frame is delimited by tx_snoop_valid going 1 -> 0 (the sim stub
    -- de-asserts it on idle cycles).
    -- ----------------------------------------------------------------
    snoop: process(clk125MHz)
        alias snoop_byte  is <<signal .tb_harness.i_dut.i_tx_interface.i_tx_rgmii.tx_snoop_byte  : std_logic_vector(7 downto 0)>>;
        alias snoop_valid is <<signal .tb_harness.i_dut.i_tx_interface.i_tx_rgmii.tx_snoop_valid : std_logic>>;
        variable len : integer := 0;
        variable was_valid : std_logic := '0';
    begin
        if rising_edge(clk125MHz) then
            if snoop_valid = '1' then
                if len < rx_frame_buf'length then
                    rx_frame_buf(len) <= snoop_byte;
                    len := len + 1;
                end if;
                rx_frame_ready <= false;
                was_valid := '1';
            elsif was_valid = '1' then
                rx_frame_len   <= len;
                rx_frame_ready <= true;
                len            := 0;
                was_valid      := '0';
            end if;
        end if;
    end process;

    -- ----------------------------------------------------------------
    -- Stimulus: drive frames onto the RX byte interface, then check.
    -- ----------------------------------------------------------------
    stim: process

        -- Drive N idle symbols (0xDD with input_data_present='0') so that
        -- detect_speed_and_reassemble_bytes sets link_1000mb='1'. Without
        -- this the RX pipeline silently drops everything.
        procedure drive_idle(n : positive) is
        begin
            wait until rising_edge(clk125Mhz);
            input_empty        <= '0';
            input_data         <= x"DD";
            input_data_present <= '0';
            for i in 1 to n loop
                wait until rising_edge(clk125Mhz);
            end loop;
        end procedure;

        procedure push_frame(constant bytes : byte_array_t) is
        begin
            -- Switch from idle to frame; input_empty stays '0'
            wait until rising_edge(clk125Mhz);
            input_empty <= '0';
            for i in bytes'range loop
                input_data         <= bytes(i);
                input_data_present <= '1';
                loop
                    wait until rising_edge(clk125Mhz);
                    exit when input_read = '1';
                end loop;
            end loop;
            -- Trail with idle symbols so active_data drops cleanly
            input_data         <= x"DD";
            input_data_present <= '0';
            for i in 1 to 4 loop
                wait until rising_edge(clk125Mhz);
            end loop;
            input_empty <= '1';
        end procedure;

        constant sender_mac : std_logic_vector(47 downto 0) := x"A0_B3_CC_4C_F9_EF";
        constant sender_ip  : std_logic_vector(31 downto 0) := x"0A_00_00_01";
        variable n_passed   : integer := 0;
        variable n_failed   : integer := 0;
    begin
        wait for 500 ns;
        -- Let detect_speed_and_reassemble_bytes lock onto the 1Gb link
        drive_idle(64);

        report "=== Scenario 1: ARP request -> ARP reply ===";
        push_frame(make_arp_request(sender_mac, sender_ip, our_ip));

        for i in 0 to 5000 loop
            exit when rx_frame_ready;
            wait until rising_edge(clk125Mhz);
        end loop;

        if not rx_frame_ready then
            report "FAIL: no TX frame observed after ARP request" severity error;
            n_failed := n_failed + 1;
        else
            -- TX pipeline prepends 8-byte preamble before the frame, so wire indices shift by 8
            if rx_frame_len < 50 then
                report "FAIL: reply too short (" & integer'image(rx_frame_len) & " bytes)" severity error;
                n_failed := n_failed + 1;
            elsif rx_frame_buf(20) /= x"08" or rx_frame_buf(21) /= x"06" then
                report "FAIL: EtherType not ARP" severity error;
                n_failed := n_failed + 1;
            elsif rx_frame_buf(28) /= x"00" or rx_frame_buf(29) /= x"02" then
                report "FAIL: not ARP reply opcode" severity error;
                n_failed := n_failed + 1;
            -- frame byte 14..19 = src MAC; with 8-byte preamble, indices 22..27
            -- our_mac is stored byte-reversed; wire byte i = our_mac(7+i*8 : i*8)
            elsif rx_frame_buf(14) /= our_mac( 7 downto  0) or
                  rx_frame_buf(15) /= our_mac(15 downto  8) or
                  rx_frame_buf(16) /= our_mac(23 downto 16) or
                  rx_frame_buf(17) /= our_mac(31 downto 24) or
                  rx_frame_buf(18) /= our_mac(39 downto 32) or
                  rx_frame_buf(19) /= our_mac(47 downto 40) then
                report "FAIL: source MAC in reply is not our_mac" severity error;
                n_failed := n_failed + 1;
            else
                report "PASS: ARP reply received with correct MAC";
                n_passed := n_passed + 1;
            end if;
        end if;

        report "=== SUMMARY: " & integer'image(n_passed) & " passed, " & integer'image(n_failed) & " failed ===";
        if n_failed = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report integer'image(n_failed) & " TEST(S) FAILED" severity failure;
        end if;
        wait;
    end process;

end sim;
