----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz> (original 16-byte version)
--
-- Module Name: tcp_engine_content_memory - Behavioral
--
-- Description: BRAM holding the static content the TCP engine ships to any
--              client that completes a handshake and sends data. The engine
--              streams CONTENT_LEN bytes starting at address 0; the contents
--              are an HTTP/1.0 response with a small HTML body.
--
--              Address is 7 bits so the BRAM holds 128 bytes; CONTENT_LEN
--              tells tcp_engine how much to actually send. Trailing entries
--              are zero pad.
--
-- Response layout (119 bytes total):
--   "HTTP/1.0 200 OK\r\n"                         (17 bytes)
--   "Content-Type: text/html\r\n"                 (25 bytes)
--   "Content-Length: 55\r\n"                      (20 bytes)
--   "\r\n"                                        ( 2 bytes)
--   "<html><body><h1>Hello from the FPGA!</h1></body></html>"  (55 bytes)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tcp_engine_content_memory is
    Port ( clk     : in  STD_LOGIC;
           address : in  STD_LOGIC_VECTOR (15 downto 0);
           data    : out STD_LOGIC_VECTOR ( 7 downto 0));
end tcp_engine_content_memory;

architecture Behavioral of tcp_engine_content_memory is
    type a_mem is array(0 to 127) of std_logic_vector(7 downto 0);
    -- HTTP response: 17 + 25 + 20 + 2 + 55 = 119 bytes, see header.
    signal mem : a_mem := (
        -- "HTTP/1.0 200 OK\r\n"
        x"48", x"54", x"54", x"50", x"2F", x"31", x"2E", x"30",
        x"20", x"32", x"30", x"30", x"20", x"4F", x"4B", x"0D", x"0A",
        -- "Content-Type: text/html\r\n"
        x"43", x"6F", x"6E", x"74", x"65", x"6E", x"74", x"2D",
        x"54", x"79", x"70", x"65", x"3A", x"20", x"74", x"65",
        x"78", x"74", x"2F", x"68", x"74", x"6D", x"6C", x"0D", x"0A",
        -- "Content-Length: 55\r\n"
        x"43", x"6F", x"6E", x"74", x"65", x"6E", x"74", x"2D",
        x"4C", x"65", x"6E", x"67", x"74", x"68", x"3A", x"20",
        x"35", x"35", x"0D", x"0A",
        -- "\r\n" (end of headers)
        x"0D", x"0A",
        -- "<html><body><h1>Hello from the FPGA!</h1></body></html>"
        x"3C", x"68", x"74", x"6D", x"6C", x"3E",                     -- <html>
        x"3C", x"62", x"6F", x"64", x"79", x"3E",                     -- <body>
        x"3C", x"68", x"31", x"3E",                                   -- <h1>
        x"48", x"65", x"6C", x"6C", x"6F", x"20",                     -- "Hello "
        x"66", x"72", x"6F", x"6D", x"20",                            -- "from "
        x"74", x"68", x"65", x"20",                                   -- "the "
        x"46", x"50", x"47", x"41", x"21",                            -- "FPGA!"
        x"3C", x"2F", x"68", x"31", x"3E",                            -- </h1>
        x"3C", x"2F", x"62", x"6F", x"64", x"79", x"3E",              -- </body>
        x"3C", x"2F", x"68", x"74", x"6D", x"6C", x"3E",              -- </html>
        -- pad to 128
        others => x"00");
begin
    process(clk)
    begin
        if rising_edge(clk) then
            data <= mem(to_integer(unsigned(address(6 downto 0))));
        end if;
    end process;
end Behavioral;
