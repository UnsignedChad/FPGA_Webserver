-- ecp5 version of clocking. takes the 25 mhz osc on pin P6 and produces
-- 125 mhz + 125 mhz @ 90 deg for the rgmii tx ddr path.
--
-- pll math: VCO = 25 * CLKFB_DIV / CLKI_DIV. ECP5 VCO range is 400-800 MHz.
-- 25 * 20 = 500 MHz -> /4 = 125 MHz, /4 with 90 deg cphase shift = 125 @ 90.
-- 1 CPHASE step at 500 MHz vco = 45 deg of the 125 mhz clock, so cphase=2
-- gives 90 deg shift. exact phase may need empirical tweak after first
-- bringup, see ecppll -i 25 -o 125 --phase=90 for a generated reference.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library ecp5u;
use ecp5u.components.all;

entity clocking is
    Port ( clk100MHz   : in  STD_LOGIC;   -- misnamed; on the 5a-75b this is 25 mhz from P6
           clk125MHz   : out STD_LOGIC;
           clk125MHz90 : out STD_LOGIC);
end clocking;

architecture ecp5 of clocking is
    signal clk_op : std_logic;
    signal clk_os : std_logic;
    signal lock_o : std_logic;
begin

pll : EHXPLLL
    generic map (
        CLKI_DIV      => 1,
        CLKFB_DIV     => 5,
        CLKOP_DIV     => 4,
        CLKOS_DIV     => 4,
        CLKOS2_DIV    => 1,
        CLKOS3_DIV    => 1,
        CLKOP_ENABLE  => "ENABLED",
        CLKOS_ENABLE  => "ENABLED",
        CLKOS2_ENABLE => "DISABLED",
        CLKOS3_ENABLE => "DISABLED",
        CLKOP_CPHASE  => 3,
        CLKOS_CPHASE  => 5,           -- +2 vs CLKOP -> ~90 deg at 125 mhz
        CLKOP_FPHASE  => 0,
        CLKOS_FPHASE  => 0,
        FEEDBK_PATH   => "CLKOP",
        CLKOP_TRIM_POL    => "FALLING",
        CLKOP_TRIM_DELAY  => 0,
        CLKOS_TRIM_POL    => "FALLING",
        CLKOS_TRIM_DELAY  => 0,
        OUTDIVIDER_MUXA => "DIVA",
        OUTDIVIDER_MUXB => "DIVB",
        OUTDIVIDER_MUXC => "DIVC",
        OUTDIVIDER_MUXD => "DIVD",
        PLL_LOCK_MODE => 0,
        STDBY_ENABLE  => "DISABLED",
        PLLRST_ENA    => "DISABLED",
        INTFB_WAKE    => "DISABLED",
        DPHASE_SOURCE => "DISABLED"
    )
    port map (
        CLKI         => clk100MHz,   -- really 25 mhz, see comment above
        CLKFB        => clk_op,
        PHASESEL0    => '0',
        PHASESEL1    => '0',
        PHASEDIR     => '0',
        PHASESTEP    => '0',
        PHASELOADREG => '0',
        STDBY        => '0',
        PLLWAKESYNC  => '0',
        RST          => '0',
        ENCLKOP      => '0',
        ENCLKOS      => '0',
        ENCLKOS2     => '0',
        ENCLKOS3     => '0',
        CLKOP        => clk_op,
        CLKOS        => clk_os,
        CLKOS2       => open,
        CLKOS3       => open,
        LOCK         => lock_o
    );

    clk125MHz   <= clk_op;
    clk125MHz90 <= clk_os;

end ecp5;
