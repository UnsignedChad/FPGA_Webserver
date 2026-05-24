-- 4k-deep byte fifo between tx_add_preamble and tx_rgmii. soaks up the
-- arbiter writing at 125 MHz while tx_rgmii drains slowly when the phy
-- has auto-negotiated to 100 mbps (one byte per 10 cycles) or 10 mbps
-- (one byte per 100 cycles). also generates the data_enable pulse that
-- tx_rgmii expects as a clock-enable for the drain side.
--
-- backpressure: almost_full goes high when more than 2500 entries are
-- in flight (room for one max-sized packet plus loop latency), and
-- gets fed back to tx_arbiter as 'not ready' so it stops granting new
-- packets until the fifo drains.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tx_speed_fifo is
    Port (
        clk : in std_logic;

        link_10mb   : in std_logic;
        link_100mb  : in std_logic;
        link_1000mb : in std_logic;

        wr_data       : in  std_logic_vector(7 downto 0);
        wr_data_valid : in  std_logic;

        rd_data       : out std_logic_vector(7 downto 0) := (others => '0');
        rd_data_valid : out std_logic := '0';
        rd_enable     : out std_logic := '0';

        almost_full : out std_logic := '0');
end tx_speed_fifo;

architecture rtl of tx_speed_fifo is
    constant DEPTH       : integer := 4096;
    constant ALMOST_FULL_LEVEL : integer := 2500;

    type mem_t is array (0 to DEPTH-1) of std_logic_vector(8 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    signal wr_ptr : unsigned(11 downto 0) := (others => '0');
    signal rd_ptr : unsigned(11 downto 0) := (others => '0');
    signal count  : unsigned(12 downto 0) := (others => '0');

    -- pulse generator: 1 in N cycles depending on link speed
    signal divider     : unsigned(6 downto 0) := (others => '0');
    signal pulse       : std_logic := '0';
    signal pulse_modulus : unsigned(6 downto 0) := to_unsigned(1, 7);

    signal out_word : std_logic_vector(8 downto 0) := (others => '0');
begin
    rd_data       <= out_word(7 downto 0);
    rd_data_valid <= out_word(8);
    rd_enable     <= pulse;

    -- pick the divider modulus from link speed; default to gigabit (=1)
    process(clk)
    begin
        if rising_edge(clk) then
            if link_1000mb = '1' then
                pulse_modulus <= to_unsigned(1, 7);
            elsif link_100mb = '1' then
                pulse_modulus <= to_unsigned(10, 7);
            elsif link_10mb = '1' then
                pulse_modulus <= to_unsigned(100, 7);
            end if;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            -- speed pulse
            if divider + 1 >= pulse_modulus then
                divider <= (others => '0');
                pulse   <= '1';
            else
                divider <= divider + 1;
                pulse   <= '0';
            end if;

            -- write side
            if wr_data_valid = '1' and count < DEPTH then
                mem(to_integer(wr_ptr)) <= '1' & wr_data;
                wr_ptr <= wr_ptr + 1;
            end if;

            -- read side: pop one entry per pulse if anything is queued
            if pulse = '1' and count /= 0 then
                out_word <= mem(to_integer(rd_ptr));
                rd_ptr <= rd_ptr + 1;
            elsif pulse = '1' then
                out_word <= (others => '0');
            end if;

            -- count tracker (single source of truth)
            if wr_data_valid = '1' and count < DEPTH then
                if pulse = '1' and count /= 0 then
                    count <= count;          -- write+read cancels
                else
                    count <= count + 1;
                end if;
            else
                if pulse = '1' and count /= 0 then
                    count <= count - 1;
                end if;
            end if;

            if count > to_unsigned(ALMOST_FULL_LEVEL, 13) then
                almost_full <= '1';
            else
                almost_full <= '0';
            end if;
        end if;
    end process;
end rtl;
