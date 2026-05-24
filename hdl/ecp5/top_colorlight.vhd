-- top-level wrapper for the colorlight 5a-75b build. wraps the existing
-- FPGA_webserver entity (originally targeted at the nexys video) so the
-- ports line up with the 5a-75b pinout in colorlight_5a_75b.lpf:
-- one 25 mhz clock, one button, one open-drain led, and the rgmii pins
-- for phy0 (J1 port). the inner clocking module is the ecp5 version
-- which knows the input is 25 mhz despite the legacy port name.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top_colorlight is
    port (
        clk25mhz  : in    std_logic;
        btn       : in    std_logic;
        led_n     : out   std_logic;
        eth_rst_n : out   std_logic;
        eth_mdc   : out   std_logic;
        eth_mdio  : inout std_logic;
        eth_rxck  : in    std_logic;
        eth_rxctl : in    std_logic;
        eth_rxd   : in    std_logic_vector(3 downto 0);
        eth_txck  : out   std_logic;
        eth_txctl : out   std_logic;
        eth_txd   : out   std_logic_vector(3 downto 0));
end top_colorlight;

architecture rtl of top_colorlight is
    signal switches : std_logic_vector(3 downto 0);
    signal leds     : std_logic_vector(7 downto 0);
begin
    -- single button -> switches(0); the rest are tied off
    switches <= "000" & (not btn);

    -- map LED 0 (originally the link-status indicator) onto the single
    -- onboard led. active-low because of open-drain output.
    led_n <= not leds(0);

    i_fws : entity work.FPGA_webserver
        port map (
            clk100MHz => clk25mhz,   -- actually 25 mhz; ecp5 PLL handles the math
            switches  => switches,
            leds      => leds,
            eth_int_b => '1',        -- 5a-75b doesnt wire interrupt to the fpga
            eth_pme_b => '1',        -- nor pme
            eth_rst_b => eth_rst_n,
            eth_mdc   => eth_mdc,
            eth_mdio  => eth_mdio,
            eth_rxck  => eth_rxck,
            eth_rxctl => eth_rxctl,
            eth_rxd   => eth_rxd,
            eth_txck  => eth_txck,
            eth_txctl => eth_txctl,
            eth_txd   => eth_txd);
end rtl;
