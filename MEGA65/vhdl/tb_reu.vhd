library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;

entity tb_reu is
end entity tb_reu;

architecture simulation of tb_reu is

   signal cnt               : std_logic_vector(4 downto 0) := (others => '0');
   signal clk               : std_logic;
   signal rst               : std_logic;
   signal cfg               : std_logic_vector(1 downto 0);
   signal dma_req           : std_logic;
   signal dma_cycle         : std_logic;
   signal dma_addr          : std_logic_vector(15 downto 0);
   signal dma_dout          : std_logic_vector(7 downto 0);
   signal dma_din           : std_logic_vector(7 downto 0);
   signal dma_we            : std_logic;
   signal ram_cycle         : std_logic;
   signal ram_cycle_reu     : std_logic;
   signal ram_addr          : std_logic_vector(24 downto 0);
   signal ram_dout          : std_logic_vector(7 downto 0);
   signal ram_din           : std_logic_vector(7 downto 0);
   signal ram_we            : std_logic;
   signal ram_cs            : std_logic;
   signal cpu_addr          : unsigned(15 downto 0);
   signal cpu_dout          : unsigned(7 downto 0);
   signal cpu_din           : unsigned(7 downto 0);
   signal cpu_we            : std_logic;
   signal cpu_cs            : std_logic;
   signal irq               : std_logic;

   signal avm_clk           : std_logic;
   signal avm_rst           : std_logic;
   signal avm_write         : std_logic;
   signal avm_read          : std_logic;
   signal avm_address       : std_logic_vector(31 downto 0);
   signal avm_writedata     : std_logic_vector(15 downto 0);
   signal avm_byteenable    : std_logic_vector(1 downto 0);
   signal avm_burstcount    : std_logic_vector(7 downto 0);
   signal avm_readdata      : std_logic_vector(15 downto 0);
   signal avm_readdatavalid : std_logic;
   signal avm_waitrequest   : std_logic;

   component reu
      port (
         clk         : in  std_logic;
         reset       : in  std_logic;
         cfg         : in  std_logic_vector(1 downto 0);
         dma_req     : out std_logic;
         dma_cycle   : in  std_logic;
         dma_addr    : out std_logic_vector(15 downto 0);
         dma_dout    : out std_logic_vector(7 downto 0);
         dma_din     : in  std_logic_vector(7 downto 0);
         dma_we      : out std_logic;
         ram_cycle   : in  std_logic;
         ram_addr    : out std_logic_vector(24 downto 0);
         ram_dout    : out std_logic_vector(7 downto 0);
         ram_din     : in  std_logic_vector(7 downto 0);
         ram_we      : out std_logic;
         ram_cs      : out std_logic;
         cpu_addr    : in  unsigned(15 downto 0);
         cpu_dout    : in  unsigned(7 downto 0);
         cpu_din     : out unsigned(7 downto 0);
         cpu_we      : in  std_logic;
         cpu_cs      : in  std_logic;
         irq         : out std_logic
      );
   end component reu;

   -- This defines a type containing an array of bytes
   type ram_t is array (0 to 255) of std_logic_vector(7 downto 0);
   signal ram : ram_t := (0 => X"11",
                          1 => X"22",
                          2 => X"33",
                          3 => X"44",
                          4 => X"55",
                          others => X"UU");

begin

   -------------------
   -- Clock and reset
   -------------------

   p_clk : process
   begin
      clk <= '1';
      wait for 15 ns;
      clk <= '0';
      wait for 15 ns;
   end process p_clk;

   p_rst : process
   begin
      rst <= '1';
      wait for 200 ns;
      wait until clk = '1';
      rst <= '0';
      wait;
   end process p_rst;


   -----------------------
   -- CPU synchronization
   -----------------------

   p_cnt : process (clk)
   begin
      if rising_edge(clk) then
         cnt <= cnt + 1;
      end if;
   end process p_cnt;

--                     1         2         3
--           01234567890123456789012345678901
-- dma_cycle ________________****************
-- ram_cycle ____****________________________
-- cpu_cs    ________________****************

   ram_cycle <= '1' when cnt >=  4 and cnt <=  7 else '0';
   dma_cycle <= '1' when cnt >= 16 and cnt <= 31 else '0';


   -----------------------
   -- Main test procedure
   -----------------------

   p_test : process
      procedure cpu_write(addr : std_logic_vector(15 downto 0); data : std_logic_vector(7 downto 0)) is
      begin
         wait until dma_cycle = '1';
         cpu_addr <= unsigned(addr);
         cpu_dout <= unsigned(data);
         cpu_we   <= '1';
         cpu_cs   <= '1';
         wait until dma_cycle = '0';
         cpu_we <= '0';
         cpu_cs <= '0';
      end procedure cpu_write;

      procedure write_to_hr(ram_addr : std_logic_vector(15 downto 0);
                            hr_addr  : std_logic_vector(23 downto 0);
                            length   : std_logic_vector(15 downto 0)) is
      begin
         cpu_write(X"DF02", ram_addr( 7 downto  0));
         cpu_write(X"DF03", ram_addr(15 downto  8));
         cpu_write(X"DF04",  hr_addr( 7 downto  0));
         cpu_write(X"DF05",  hr_addr(15 downto  8));
         cpu_write(X"DF06",  hr_addr(23 downto 16));
         cpu_write(X"DF07",   length( 7 downto  0));
         cpu_write(X"DF08",   length(15 downto  8));
         cpu_write(X"DF01", X"90"); -- Write to HyperRAM
      end procedure write_to_hr;

      procedure read_from_hr(ram_addr : std_logic_vector(15 downto 0);
                             hr_addr  : std_logic_vector(23 downto 0);
                             length   : std_logic_vector(15 downto 0)) is
      begin
         cpu_write(X"DF02", ram_addr( 7 downto  0));
         cpu_write(X"DF03", ram_addr(15 downto  8));
         cpu_write(X"DF04",  hr_addr( 7 downto  0));
         cpu_write(X"DF05",  hr_addr(15 downto  8));
         cpu_write(X"DF06",  hr_addr(23 downto 16));
         cpu_write(X"DF07",   length( 7 downto  0));
         cpu_write(X"DF08",   length(15 downto  8));
         cpu_write(X"DF01", X"91"); -- Read from HyperRAM
      end procedure read_from_hr;

   begin
      cpu_cs <= '0';
      wait for 500 ns;
      wait until clk = '1';

      assert ram(0) = X"11";
      assert ram(1) = X"22";
      assert ram(2) = X"33";
      assert ram(3) = X"44";
      assert ram(4) = X"55";

      write_to_hr(X"0000", X"000100", X"0005");
      wait until dma_req = '0';
      wait until clk = '1';

      read_from_hr(X"0000", X"000101", X"0004");
      wait until dma_req = '0';
      wait until clk = '1';

      assert ram(0) = X"22";
      assert ram(1) = X"33";
      assert ram(2) = X"44";
      assert ram(3) = X"55";

      report "Test finished";
      wait;
   end process p_test;


   -------------------
   -- Instantiate DUT
   -------------------

   i_reu : reu
      port map (
         clk       => clk,           -- in
         reset     => rst,           -- in
         cfg       => "10",          -- in
         dma_req   => dma_req,       -- out
         dma_cycle => dma_cycle,     -- in
         dma_addr  => dma_addr,      -- out
         dma_dout  => dma_dout,      -- out
         dma_din   => dma_din,       -- in
         dma_we    => dma_we,        -- out
         ram_cycle => ram_cycle_reu, -- in
         ram_addr  => ram_addr,      -- out
         ram_dout  => ram_dout,      -- out
         ram_din   => ram_din,       -- in
         ram_we    => ram_we,        -- out
         ram_cs    => ram_cs,        -- out
         cpu_addr  => cpu_addr,      -- in
         cpu_dout  => cpu_dout,      -- in
         cpu_din   => cpu_din,       -- out
         cpu_we    => cpu_we,        -- in
         cpu_cs    => cpu_cs,        -- in
         irq       => irq            -- out
      ); -- i_reu

   p_ram : process (clk)
   begin
      if rising_edge(clk) then
         if dma_we = '1' then
            ram(to_integer(dma_addr(7 downto 0))) <= dma_dout;
         end if;
         dma_din <= ram(to_integer(dma_addr(7 downto 0)));
      end if;
   end process p_ram;


   i_reu_mapper : entity work.reu_mapper
      generic map (
         G_BASE_ADDRESS => X"0020_0000"  -- 2MW
      )
      port map (
         clk_i               => clk,
         rst_i               => rst,
         reu_ext_cycle_i     => ram_cycle,
         reu_ext_cycle_o     => ram_cycle_reu,
         reu_addr_i          => ram_addr,
         reu_dout_i          => ram_dout,
         reu_din_o           => ram_din,
         reu_we_i            => ram_we,
         reu_cs_i            => ram_cs,
         avm_write_o         => avm_write,
         avm_read_o          => avm_read,
         avm_address_o       => avm_address,
         avm_writedata_o     => avm_writedata,
         avm_byteenable_o    => avm_byteenable,
         avm_burstcount_o    => avm_burstcount,
         avm_readdata_i      => avm_readdata,
         avm_readdatavalid_i => avm_readdatavalid,
         avm_waitrequest_i   => avm_waitrequest
      ); -- i_reu_mapper

   i_avm_memory : entity work.avm_memory
      generic map (
         G_ADDRESS_SIZE => 8,
         G_DATA_SIZE    => 16
      )
      port map (
         clk_i               => clk,
         rst_i               => rst,
         avm_write_i         => avm_write,
         avm_read_i          => avm_read,
         avm_address_i       => avm_address(7 downto 0),
         avm_writedata_i     => avm_writedata,
         avm_byteenable_i    => avm_byteenable,
         avm_burstcount_i    => avm_burstcount,
         avm_readdata_o      => avm_readdata,
         avm_readdatavalid_o => avm_readdatavalid,
         avm_waitrequest_o   => avm_waitrequest
      ); -- i_avm_memory

end architecture simulation;

