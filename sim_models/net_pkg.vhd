----------------------------------------------------------------------------------
-- net_pkg - networking helpers for self-checking testbenches
--
-- Types
--   byte_array_t : unconstrained array of bytes
--
-- Helpers
--   ip_checksum         : RFC 1071 ones-complement Internet checksum
--   ip_to_wire          : convert byte-reversed-storage IP to network order
--   mac_to_wire         : convert byte-reversed-storage MAC to network order
--   make_arp_request    : raw Ethernet frame containing an ARP request
--   make_icmp_echo      : raw Ethernet frame containing an ICMP echo request
--
-- All make_* helpers prepend the 8-byte Ethernet preamble + SFD and append a
-- 4-byte placeholder FCS (the DUT does not currently validate FCS).
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package net_pkg is

    type byte_array_t is array(natural range <>) of std_logic_vector(7 downto 0);

    constant ETH_PREAMBLE : byte_array_t(0 to 7) :=
        (x"55", x"55", x"55", x"55", x"55", x"55", x"55", x"D5");

    function ip_checksum(buf : byte_array_t) return std_logic_vector;

    function make_arp_request(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        target_ip  : std_logic_vector(31 downto 0)
    ) return byte_array_t;

    function make_icmp_echo(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        dut_mac    : std_logic_vector(47 downto 0);
        dut_ip     : std_logic_vector(31 downto 0);
        ident      : std_logic_vector(15 downto 0);
        seq        : std_logic_vector(15 downto 0);
        payload    : byte_array_t
    ) return byte_array_t;

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
        for i in 0 to 5 loop
            f(14 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        f(20) := x"08"; f(21) := x"06";          -- EtherType ARP
        f(22) := x"00"; f(23) := x"01";          -- HW Ethernet
        f(24) := x"08"; f(25) := x"00";          -- Proto IPv4
        f(26) := x"06"; f(27) := x"04";          -- HW len, proto len
        f(28) := x"00"; f(29) := x"01";          -- Operation = request
        for i in 0 to 5 loop
            f(30 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        for i in 0 to 3 loop
            f(36 + i) := sender_ip(31 - i*8 downto 24 - i*8);
        end loop;
        f(40 to 45) := (x"00", x"00", x"00", x"00", x"00", x"00");
        for i in 0 to 3 loop
            f(46 + i) := target_ip(31 - i*8 downto 24 - i*8);
        end loop;
        f(68) := x"DE"; f(69) := x"AD"; f(70) := x"BE"; f(71) := x"EF";
        return f;
    end function;

    function make_icmp_echo(
        sender_mac : std_logic_vector(47 downto 0);
        sender_ip  : std_logic_vector(31 downto 0);
        dut_mac    : std_logic_vector(47 downto 0);
        dut_ip     : std_logic_vector(31 downto 0);
        ident      : std_logic_vector(15 downto 0);
        seq        : std_logic_vector(15 downto 0);
        payload    : byte_array_t
    ) return byte_array_t is
        constant pl_len   : integer := payload'length;
        constant icmp_len : integer := 8 + pl_len;       -- ICMP header (8) + payload
        constant ip_len   : integer := 20 + icmp_len;    -- IP header (20) + ICMP
        constant eth_len  : integer := 14 + ip_len;      -- Eth header (14) + IP
        -- Pad to 46-byte minimum Ethernet payload; with our typical ping
        -- payload of >= 18 bytes no padding is needed.
        function max0(x : integer) return integer is
        begin
            if x > 0 then return x; else return 0; end if;
        end;
        constant pad_bytes   : integer := max0(46 - ip_len);
        constant frame_bytes : integer := eth_len + pad_bytes + 4;  -- + FCS
        constant total       : integer := 8 + frame_bytes;          -- + preamble
        variable f : byte_array_t(0 to total - 1) := (others => x"00");

        variable ip_buf   : byte_array_t(0 to 19);
        variable icmp_buf : byte_array_t(0 to icmp_len - 1);
        variable ck       : std_logic_vector(15 downto 0);
        variable ip_len_v : std_logic_vector(15 downto 0);
    begin
        f(0 to 7) := ETH_PREAMBLE;
        -- dst MAC = dut_mac
        for i in 0 to 5 loop
            f(8 + i) := dut_mac(47 - i*8 downto 40 - i*8);
        end loop;
        -- src MAC
        for i in 0 to 5 loop
            f(14 + i) := sender_mac(47 - i*8 downto 40 - i*8);
        end loop;
        -- EtherType IPv4
        f(20) := x"08"; f(21) := x"00";

        -- Build ICMP message (header + payload), compute checksum
        icmp_buf := (others => x"00");
        icmp_buf(0) := x"08";       -- Type 8 = echo request
        icmp_buf(1) := x"00";       -- Code 0
        icmp_buf(2) := x"00";       -- checksum hi (placeholder)
        icmp_buf(3) := x"00";       -- checksum lo
        icmp_buf(4) := ident(15 downto 8);
        icmp_buf(5) := ident( 7 downto 0);
        icmp_buf(6) := seq(15 downto 8);
        icmp_buf(7) := seq( 7 downto 0);
        for i in 0 to pl_len - 1 loop
            icmp_buf(8 + i) := payload(payload'low + i);
        end loop;
        ck := ip_checksum(icmp_buf);
        icmp_buf(2) := ck(15 downto 8);
        icmp_buf(3) := ck( 7 downto 0);

        -- Build IP header
        ip_len_v := std_logic_vector(to_unsigned(ip_len, 16));
        ip_buf(0)  := x"45";           -- Version 4, IHL 5
        ip_buf(1)  := x"00";           -- TOS
        ip_buf(2)  := ip_len_v(15 downto 8);
        ip_buf(3)  := ip_len_v( 7 downto 0);
        ip_buf(4)  := x"00"; ip_buf(5) := x"01";   -- Ident
        ip_buf(6)  := x"00"; ip_buf(7) := x"00";   -- Flags + frag offset
        ip_buf(8)  := x"40";           -- TTL 64
        ip_buf(9)  := x"01";           -- Protocol ICMP
        ip_buf(10) := x"00"; ip_buf(11) := x"00";  -- checksum (placeholder)
        for i in 0 to 3 loop
            ip_buf(12 + i) := sender_ip(31 - i*8 downto 24 - i*8);
        end loop;
        for i in 0 to 3 loop
            ip_buf(16 + i) := dut_ip(31 - i*8 downto 24 - i*8);
        end loop;
        ck := ip_checksum(ip_buf);
        ip_buf(10) := ck(15 downto 8);
        ip_buf(11) := ck( 7 downto 0);

        -- Splice into frame
        for i in 0 to 19 loop
            f(22 + i) := ip_buf(i);
        end loop;
        for i in 0 to icmp_len - 1 loop
            f(42 + i) := icmp_buf(i);
        end loop;
        -- pad + placeholder FCS (last 4 bytes) already zero
        f(total - 4) := x"DE"; f(total - 3) := x"AD";
        f(total - 2) := x"BE"; f(total - 1) := x"EF";
        return f;
    end function;

end package body net_pkg;
