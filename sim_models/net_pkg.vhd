----------------------------------------------------------------------------------
-- net_pkg - networking helpers for self-checking testbenches
--
-- - byte_array_t:     unconstrained vector-of-bytes
-- - ip_checksum:      RFC 1071 ones-complement Internet checksum
-- - make_arp_request: build a raw Ethernet frame containing an ARP request
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package net_pkg is

    type byte_array_t is array(natural range <>) of std_logic_vector(7 downto 0);

    constant ETH_PREAMBLE : byte_array_t(0 to 7) :=
        (x"55", x"55", x"55", x"55", x"55", x"55", x"55", x"D5");

    function make_arp_request(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        target_ip  : std_logic_vector(31 downto 0)
    ) return byte_array_t;

    function ip_checksum(buf : byte_array_t) return std_logic_vector;

end package net_pkg;

package body net_pkg is

    function ip_checksum(buf : byte_array_t) return std_logic_vector is
        variable sum  : unsigned(31 downto 0) := (others => '0');
        variable word : unsigned(15 downto 0);
        variable i    : integer := buf'low;
    begin
        while i <= buf'high loop
            if i = buf'high then
                word := unsigned(buf(i)) & x"00";
            else
                word := unsigned(buf(i)) & unsigned(buf(i + 1));
            end if;
            sum := sum + word;
            i := i + 2;
        end loop;
        while sum(31 downto 16) /= 0 loop
            sum := ("0000000000000000" & sum(31 downto 16)) +
                   ("0000000000000000" & sum(15 downto 0));
        end loop;
        return std_logic_vector(not sum(15 downto 0));
    end function;

    function make_arp_request(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        target_ip  : std_logic_vector(31 downto 0)
    ) return byte_array_t is
        variable f : byte_array_t(0 to 71) := (others => x"00");
    begin
        f(0 to 7) := ETH_PREAMBLE;
        -- Eth dst MAC = broadcast
        f(8 to 13) := (x"FF", x"FF", x"FF", x"FF", x"FF", x"FF");
        -- Eth src MAC
        for i in 0 to 5 loop
            f(14 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        -- EtherType ARP
        f(20) := x"08"; f(21) := x"06";
        -- ARP: HW Ethernet
        f(22) := x"00"; f(23) := x"01";
        -- Proto IPv4
        f(24) := x"08"; f(25) := x"00";
        -- HW len, proto len
        f(26) := x"06"; f(27) := x"04";
        -- Operation = request
        f(28) := x"00"; f(29) := x"01";
        -- Sender MAC
        for i in 0 to 5 loop
            f(30 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        -- Sender IP
        for i in 0 to 3 loop
            f(36 + i) := sender_ip(31 - i*8 downto 24 - i*8);
        end loop;
        -- Target MAC (unknown in a request)
        f(40 to 45) := (x"00", x"00", x"00", x"00", x"00", x"00");
        -- Target IP
        for i in 0 to 3 loop
            f(46 + i) := target_ip(31 - i*8 downto 24 - i*8);
        end loop;
        -- bytes 50..67 zero-padded (Ethernet min frame), 68..71 placeholder FCS
        f(68) := x"DE"; f(69) := x"AD"; f(70) := x"BE"; f(71) := x"EF";
        return f;
    end function;

end package body net_pkg;
