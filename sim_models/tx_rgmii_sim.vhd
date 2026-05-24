----------------------------------------------------------------------------------
-- Simulation-only behavioural replacement for tx_rgmii.
--
-- The synthesis version uses Xilinx UNISIM ODDR primitives, which GHDL cannot
-- analyse without a vendor library install. This stub has the same entity
-- interface so tx_interface can instantiate it unchanged.
--
-- The eth_tx* outputs are driven with a simple non-DDR pattern; the harness
-- does not check them. Instead it observes the byte stream via the
-- tx_snoop_* signals using a VHDL-2008 external name.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tx_rgmii is
    Port ( clk         : in  STD_LOGIC;
           clk90       : in  STD_LOGIC;
           phy_ready   : in  STD_LOGIC;

           data        : in  STD_LOGIC_VECTOR (7 downto 0);
           data_valid  : in  STD_LOGIC;
           data_enable : in  STD_LOGIC := '1';
           data_error  : in  STD_LOGIC;

           eth_txck    : out STD_LOGIC := '0';
           eth_txctl   : out STD_LOGIC := '0';
           eth_txd     : out STD_LOGIC_VECTOR (3 downto 0) := (others => '0'));
end tx_rgmii;

architecture Sim of tx_rgmii is
    -- Observable byte stream. Snooped by the testbench harness using
    -- VHDL-2008 external names: <<.tb.dut.i_tx_interface.i_tx_rgmii.tx_snoop_byte>>
    signal tx_snoop_byte    : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_snoop_valid   : std_logic := '0';
    signal tx_snoop_error   : std_logic := '0';
begin

    snoop: process(clk)
    begin
        if rising_edge(clk) then
            if data_enable = '1' then
                tx_snoop_byte  <= data;
                tx_snoop_valid <= data_valid;
                tx_snoop_error <= data_error;
            else
                -- between clock-enable beats, hold valid low so each byte is observed once
                tx_snoop_valid <= '0';
            end if;
        end if;
    end process;

    -- Drive PHY pins with something non-floating; not checked by tests.
    eth_txck  <= clk;
    eth_txctl <= data_valid and data_enable;
    eth_txd   <= data(3 downto 0);

end Sim;
