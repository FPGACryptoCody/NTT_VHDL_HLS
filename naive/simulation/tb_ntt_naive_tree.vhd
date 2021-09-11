-- Title: Testbench, Barret Reduction
-- Created by: Cody Emerson
-- Date: 6/23/2021
-- Target: Xilinx Ultrascale
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- Description: Simulate and Verify barret_reduction.vhd
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use std.textio.all;

library work;
use work.helper_functions.all;

entity tb_ntt_naive is
   generic( 
      G_MODULUS            : std_logic_vector:="11000000000001";
      -- Barret Reduction Parameters
      G_R                  : std_logic_vector:="101010101010011";
      G_K2                 : std_logic_vector:="11100"
   );
   port(
      SIM_FIN              : out std_logic
   );
end tb_ntt_naive;

architecture tb of tb_ntt_naive is

   --clock parameters
   constant SYSTEM_CLK_PERIOD          : time := 6.25 * 1 ns;
   constant SYSTEM_ALIGN_PERIOD        : time := 40 * 1 us;
   constant SYSTEM_CLK_SKEW            : time := 0 ns;

   --signal delays
   constant RST_DELAY                  : time := 1 ns;
   constant DELAY                      : time := 0 ns;
   
   signal clk                          : std_logic;
   signal rst                          : std_logic;

                   
   constant TbPeriod                   : time := 1000 ns; 
   signal TbClock                      : std_logic := '0';
   signal TbSimEnded                   : std_logic := '0';

   -- DUT
   signal din_int                      : std_logic_array(2 downto 0)(G_MODULUS'length -1 downto 0);
   signal dout_int                     : std_logic_array(2 downto 0)(G_MODULUS'length -1 downto 0); 
   signal ena_int                      : std_logic;
   signal vld_int                      : std_logic;
   signal ena_cnt                      : std_logic_vector(1 downto 0):="00";

begin

   process
   begin
      wait until falling_edge(RST);
      wait until rising_edge(CLK);
      wait until rising_edge(CLK);
      ena_int <= '1';
      din_int(0) <= std_logic_vector(to_unsigned(0,G_MODULUS'length));
      din_int(1) <= std_logic_vector(to_unsigned(1,G_MODULUS'length));
      din_int(2) <= std_logic_vector(to_unsigned(2,G_MODULUS'length));
      wait until rising_edge(CLK);
      din_int(0) <= std_logic_vector(to_unsigned(100,G_MODULUS'length));
      din_int(1) <= std_logic_vector(to_unsigned(120,G_MODULUS'length));
      din_int(2) <= std_logic_vector(to_unsigned(140,G_MODULUS'length));
      wait until rising_edge(CLK);
      din_int(0) <= std_logic_vector(to_unsigned(6,G_MODULUS'length));
      din_int(1) <= std_logic_vector(to_unsigned(7,G_MODULUS'length));
      din_int(2) <= std_logic_vector(to_unsigned(8,G_MODULUS'length));
      wait until rising_edge(CLK);
      ena_int <= '0';

   wait;
   end process;

   dut: entity work.ntt_naive_tree
   generic map(
      G_NUM_IN_PIPES       => 1,                  -- : natural:=1;      
      G_NUM_OUT_PIPES      => 1,                  -- : natural:=1;      
      G_USE_RST            => '1',                -- : std_logic:='0';   
      G_IS_SYNC_RST        => '1',                -- : std_logic:='1';   
      G_USE_STATIC_MODULUS => '1',                -- : std_logic:= '1';  
      G_GENERATOR          =>  6240,              -- : positive:=2;     
      G_R                  => G_R,                -- : std_logic_vector:=x"9";
      G_K2                 => G_K2,               -- : std_logic_vector:="110";
      G_MODULUS            => G_MODULUS,          -- : std_logic_vector:="111";
      G_LENGTH             => 3                   -- : positive:=2
   )
   port map(
      CLK                => CLK,           -- : in std_logic;
      RST                => RST,           -- : in std_logic;
   -- Reduction 
      R                  => (others=>'0'), -- : in std_logic_vector(15 downto 0);
      K2                 => (others=>'0'), -- : in std_logic_vector(15 downto 0);
      MODULUS            => (others=>'0'), -- : in std_logic_vector(15 downto 0);
   -- Coefficients 
      DIN                => din_int,       -- : in std_logic_array;
      ENA                => ena_int,       -- : in std_logic;
      DOUT               => dout_int,      -- : out std_logic_array;
      VLD                => vld_int        -- : out std_logic
   ); -- ntt_naive_tree;
   
   --system clock process
   clk_process: process is
   begin
      clk <= '0';
      wait for SYSTEM_CLK_SKEW;

      loop
         wait for SYSTEM_CLK_PERIOD/2;
         clk <= '1';
         wait for SYSTEM_CLK_PERIOD/2;
         clk <= '0';
      end loop;
   end process clk_process;

   --reset/enable process
   rst_proc: process is
   begin
      rst <= '1';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '1' after RST_DELAY;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0' after RST_DELAY;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait;
   end process rst_proc;
end tb;
