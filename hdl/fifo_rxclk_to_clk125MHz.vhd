-- portable replacement for the Vivado-IP fifo_rxclk_to_clk125MHz block.
-- 16-deep async FIFO carrying 10 bits (8 data + present + error) from the
-- RX clock domain to the system 125 MHz domain. Standard gray-pointer
-- design: each side keeps a binary pointer, ships a gray-coded copy
-- across via a 2-flop synchroniser, and decodes on the other side to
-- compute empty / full. depth=16 so 4 address bits, with one extra MSB
-- to disambiguate empty-vs-full.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo_rxclk_to_clk125MHz is
    Port ( rx_clk          : in  STD_LOGIC;
           rx_write        : in  STD_LOGIC                     := '1';
           rx_data         : in  STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
           rx_data_present : in  STD_LOGIC                     := '0';
           rx_data_error   : in  STD_LOGIC                     := '0';

           clk125Mhz       : in  STD_LOGIC;
           empty           : out STD_LOGIC                     := '1';
           read            : in  STD_LOGIC                     := '1';
           data            : out STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
           data_present    : out STD_LOGIC                     := '0';
           data_error      : out STD_LOGIC                     := '0');
end fifo_rxclk_to_clk125MHz;

architecture rtl of fifo_rxclk_to_clk125MHz is
    constant DEPTH      : integer := 16;
    constant PTR_BITS   : integer := 5;     -- 4 addr + 1 wrap

    type mem_t is array (0 to DEPTH-1) of std_logic_vector(9 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    -- pointers in their native clock domain (binary)
    signal wr_bin   : unsigned(PTR_BITS-1 downto 0) := (others => '0');
    signal rd_bin   : unsigned(PTR_BITS-1 downto 0) := (others => '0');

    -- gray-coded copies of each pointer; cross via 2-flop sync on the other side
    signal wr_gray  : std_logic_vector(PTR_BITS-1 downto 0) := (others => '0');
    signal rd_gray  : std_logic_vector(PTR_BITS-1 downto 0) := (others => '0');

    signal wr_gray_sync1 : std_logic_vector(PTR_BITS-1 downto 0) := (others => '0');
    signal wr_gray_sync2 : std_logic_vector(PTR_BITS-1 downto 0) := (others => '0');
    signal rd_gray_sync1 : std_logic_vector(PTR_BITS-1 downto 0) := (others => '0');
    signal rd_gray_sync2 : std_logic_vector(PTR_BITS-1 downto 0) := (others => '0');

    signal i_empty : std_logic := '1';
    signal q_word  : std_logic_vector(9 downto 0) := (others => '0');

    function bin_to_gray(b : unsigned) return std_logic_vector is
    begin
        return std_logic_vector(b xor ('0' & b(b'high downto 1)));
    end function;

begin
    empty        <= i_empty;
    data         <= q_word(7 downto 0);
    data_present <= q_word(8);
    data_error   <= q_word(9);

    -- --- write side (rx_clk domain) ---
    wr_proc: process(rx_clk)
    begin
        if rising_edge(rx_clk) then
            if rx_write = '1' then
                mem(to_integer(wr_bin(PTR_BITS-2 downto 0))) <=
                    rx_data_error & rx_data_present & rx_data;
                wr_bin <= wr_bin + 1;
            end if;
            wr_gray <= bin_to_gray(wr_bin);
            -- pull in rd_gray for the (unused here) full flag if needed
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end if;
    end process;

    -- --- read side (clk125Mhz domain) ---
    rd_proc: process(clk125Mhz)
    begin
        if rising_edge(clk125Mhz) then
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;

            if read = '1' and i_empty = '0' then
                q_word <= mem(to_integer(rd_bin(PTR_BITS-2 downto 0)));
                rd_bin <= rd_bin + 1;
            end if;
            rd_gray <= bin_to_gray(rd_bin);

            -- empty when read-side gray pointer matches the synchronised write pointer
            if bin_to_gray(rd_bin) = wr_gray_sync2 then
                i_empty <= '1';
            else
                i_empty <= '0';
            end if;
        end if;
    end process;
end rtl;
