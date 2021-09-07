-- Title: Naive Number Theoretic Transform
-- Created by: Cody Emerson
-- Date: 6/21/2021
-- Target: Xilinx Ultrascale
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- Description: Perform the Number Theoretic Transform according
-- to the dictionary definition.
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use ieee.std_logic_unsigned.all;
use ieee.numeric_std_unsigned.all; 

library work;
use work.common_math_package.all;
use work.common_types_package.all;

entity ntt_naive is
   generic(
      G_NUM_IN_PIPES       : natural:=1;      -- Number of pipelines on all inputs
      G_NUM_OUT_PIPES      : natural:=1;      -- Number of pipelines on all outputs
      G_USE_RST            : std_logic:='0';  -- '1' enable SRST port, '0' disable SRST port
      G_IS_SYNC_RST        : std_logic:='1';  -- '1' use synchronous reset, '0' use asynchronous reset
      G_USE_STATIC_MODULUS : std_logic:= '1'; -- '1' Parameters are generics, '0' parameters are ports
      G_GENERATOR          : positive:=2;     
      G_R                  : std_logic_vector:=x"9";
      G_K2                 : std_logic_vector:="110";
      G_MODULUS            : std_logic_vector:="111";
      G_LENGTH             : positive:=2
   );
   port(
      CLK                : in std_logic;
      RST                : in std_logic;
   -- Reduction 
      R                  : in std_logic_vector(15 downto 0);
      K2                 : in std_logic_vector(15 downto 0);
      MODULUS            : in std_logic_vector(15 downto 0);
   -- Coefficients 
      DIN                : in std_logic_array;
      ENA                : in std_logic;
      DOUT               : out std_logic_array;
      VLD                : out std_logic
   );
end ntt_naive;

architecture behavioral of ntt_naive is 

-- Types
   type root_array_type is array(integer range <>) of std_logic_vector(G_MODULUS'length-1 downto 0);

-- Functions
   -- For a static modulus, calculate the roots locally
   function f_calculate_roots return root_array_type is
      variable var_out_array : root_array_type(0 to G_LENGTH*2);
   begin
      for i in 0 to G_LENGTH*2 loop
         var_out_array(i) := std_logic_vector(to_unsigned(G_GENERATOR**i mod to_integer(unsigned(G_MODULUS)),G_MODULUS'length));  
      end loop;
      return var_out_array;
   end function;

-- Components
   component pipe is
   generic(
      G_RANK        : integer:=1;         -- Number of pipeline stages 
      G_IS_DELAY    : string:="FALSE";    -- "TRUE" use this block as a pipeline, "FALSE" use this block as a delay
      G_USE_RST     : std_logic:='0';     -- '1' synthesize resets, '0' do not synthesize resets
      G_IS_SYNC_RST : std_logic:='1'      -- '1' use synchronous reset, '0' use asychronous reset
   );
   port (
      CLK        : in  std_logic;         -- System Clock
      RST        : in  std_logic;         -- Reset, Can be async or sync        
      D          : in  std_logic_vector;  -- Input Data
      Q          : out std_logic_vector   -- Output Data
   );
   end component pipe;

   component barret_reduction is
   generic(
      G_USE_STATIC_MODULUS    : std_logic:='1'; -- '1' use generics for reductions, '0' use ports for reductions
      G_NUM_IN_PIPES          : natural:=1; -- Number of pipelines on all inputs
      G_NUM_OUT_PIPES         : natural:=1; -- Number of pipelines on all outputs
      G_USE_RST               : std_logic:='0'; -- '1' enable SRST port, '0' disable SRST port
      G_IS_SYNC_RST           : std_logic:='1'; -- '1' use synchronous reset, '0' use asychronous reset
   -- Static or Dynamic modulus
      G_R                     : std_logic_vector:=x"1"; -- R multiplier for x*R
      G_K2                    : std_logic_vector:=x"1"; -- Divider for x*r/4*k
      G_MODULUS               : std_logic_vector:=x"3"; -- Modulus for reduction
   -- Tweaking Pipelines
      G_NUM_RMULT_IN_PIPES    : natural:=2; -- Number of pipelines on input of R multiplier
      G_NUM_RMULT_OUT_PIPES   : natural:=3; -- Number of pipelines on output of R multiplier
      G_NUM_MODMULT_IN_PIPES  : natural:=2; -- Number of pipelines on input of Modulus multiplier
      G_NUM_MODMULT_OUT_PIPES : natural:=3; -- Number of pipelines on output of Modulus multiplier
      G_NUM_TSUB_PIPES        : natural:=0  -- Number of pipelines on output of t divider
   );
   port(
      CLK            : in std_logic;         -- System Cock
      RST            : in std_logic;         -- Synchronous Reset
   -- Config 
      R              : in std_logic_vector;  -- R multiplier for x*R
      K2             : in std_logic_vector;  -- divider for x*r/(4*k)

      MODULUS        : in std_logic_vector;   -- Modulus      
      DIN            : in std_logic_vector;   -- Input, Can be any length
      ENA            : in std_logic;          -- Ena only drives the VLD output to indicate processing is complete
      DOUT           : out std_logic_vector;  -- Output, restricted to the length of the modulus, naturally
      VLD            : out std_logic          -- '1' when dout is valid, '0' otherwise
   );
   end component barret_reduction;
   
   component multiplier is
   generic(
      G_IN_PIPES      : natural:= 2;    -- Pipe delays on A and B. 
      G_OUT_PIPES     : natural:= 2;    -- Pipe delays on P_OUT
      G_USE_RST       : std_logic:='0'; -- '1' enable resets, '0' disable resets
      G_IS_SYNC_RST   : std_logic:='1'; -- '1' use synchronous reset, '0' use asynchronous reset
      G_A_IS_SIGNED   : std_logic:='0'; -- '1' A_IN is signed, '0' A_IN is unsigned
      G_B_IS_SIGNED   : std_logic:='0'  -- '1' B_IN is signed, '0' B_IN is unsigned
   );
   port(
      CLK             : in  std_logic;
      RST             : in  std_logic;

      A_IN            : in  std_logic_vector; -- A Input
      B_IN            : in  std_logic_vector; -- B Input
      P_OUT           : out std_logic_vector  -- A*B output, A_IN'len + B_IN'len - 1 downto 0)
   );
   end component multiplier;

   component adder_2input is
   generic(
      -- Pipes
         G_NUM_IN_PIPES    : natural:=1;     -- Number of input pipelines
         G_NUM_OUT_PIPES   : natural:=1;     -- Number of output pipelines
         G_USE_RST         : std_logic:='0'; -- '1' use reset logic, '0' remove reset logic
         G_IS_SYNC_RST     : std_logic:='1'; -- '1' use synchronous reset, '0' use asynchronous reset
         -- Parameters
         G_IS_SIGNED       : std_logic:='0'; -- '1' inputs/outputs are signed binary, '0' inputs/outputs are unsigned binary
         G_IS_SUBTRATCTION : std_logic:='0'  -- '1' Add, '0' subtract
      );
   port ( 
         CLK   : in std_logic;                     -- System Clock
         RST   : in std_logic;                     -- Synchronous Reset
   
         DINA  : in std_logic_vector;              -- First Data Input
         DINB  : in std_logic_vector;              -- Second Data Input
   
         DOUT  : out std_logic_vector              -- Data Output
       );
   end component adder_2input;
-- Constants
   constant C_ZEROS   : unsigned(G_LENGTH-1 downto 0):=(others=>'0');
-- Signals
 -- Inputs
   signal root_array  : root_array_type(0 to G_LENGTH*2); 
   signal din_int     : std_logic_array(G_LENGTH -1 downto 0)(DIN(0)'range); -- Input flops
   signal ena_int     : std_logic;                 -- Input flops  
   signal vld_mult_int: std_logic;
   signal add_count   : unsigned(G_LENGTH-1 downto 0);
   signal add_count0  : unsigned(G_LENGTH-1 downto 0);

   signal bin_mult_dout    : std_logic_matrix(G_LENGTH-1 downto 0)(G_LENGTH-1 downto 0)(DIN(0)'length + G_MODULUS'length -1 downto 0);
   signal bin_sum          : std_logic_array(G_LENGTH-2 downto 0)(bin_mult_dout(0)(0)'length + G_LENGTH-2 downto 0);
   signal bin              : std_logic_array(G_LENGTH-1 downto 0)(G_MODULUS'length-1  downto 0);
   signal add_vld          : std_logic;
   signal bin_vld          : std_logic;

   signal adder_dina0      : std_logic_vector(din_int(0)'length + G_LENGTH-3 downto 0);
   signal adder_dinb0      : std_logic_vector(din_int(0)'length + G_LENGTH-3 downto 0);
   signal adder_dina       : std_logic_array(G_LENGTH-2 downto 0)(bin_mult_dout(0)(0)'length + G_LENGTH-3 downto 0);
   signal adder_dinb       : std_logic_array(G_LENGTH-2 downto 0)(bin_mult_dout(0)(0)'length + G_LENGTH-3 downto 0);
   signal bin0_sum         : std_logic_vector(din_int(0)'length + G_LENGTH-2 downto 0);
   signal bin0             : std_logic_vector(G_MODULUS'length-1 downto 0);
   signal bin0_vld         : std_logic;
   signal add0_vld         : std_logic;

begin
----------------------------------------------
-- Input Pipelines
-- Desc: Optional Input Pipelining
----------------------------------------------  
   pipe_ENA:  pipe generic map(G_RANK => G_NUM_IN_PIPES, G_USE_RST => G_USE_RST, G_IS_SYNC_RST => G_IS_SYNC_RST) 
   port map(CLK => CLK,RST => RST,D(0) => ENA , Q(0) => ena_int);
   
   gen_DIN_Pipes: for i in 0 to G_LENGTH-1 generate
      pipe_DIN: pipe generic map(G_RANK => G_NUM_IN_PIPES, G_USE_RST => G_USE_RST, G_IS_SYNC_RST => G_IS_SYNC_RST) 
      port map(CLK => CLK,RST => RST,D => DIN(i) , Q => din_int(i));
   end generate;      
----------------------------------------------
-- Calculate Roots
-- Desc: Create ROM that holds roots at build-time
----------------------------------------------  
   root_array <= f_calculate_roots;
----------------------------------------------
-- Bin 0
-- Desc: Bin 0 has zero multiplies so it has separate vhdl
----------------------------------------------  
   --Reuse the same adder for all Bin 0 Additions
   p_Adder_Reuse: process(CLK)
   begin
      if(G_USE_RST = '1' and G_IS_SYNC_RST = '0' and RST = '1') then
         add_count0 <= (others=>'0');
         adder_dina0 <= (others=>'0');
         adder_dinb0 <= (others=>'0');
         add0_vld <= '0';
      elsif(rising_edge(CLK)) then
         if(G_USE_RST = '1' and G_IS_SYNC_RST = '1' and RST = '1') then
            add_count0 <= (others=>'0');
            adder_dina0 <= (others=>'0');
            adder_dinb0 <= (others=>'0');
            add0_vld <= '0';
         else
            -- if it's the first add, you do not use the feedback as input
            if(add_count0 = C_ZEROS) then
               adder_dina0 <= std_logic_vector(resize(unsigned(din_int(0)),adder_dina0'length));
               adder_dinb0 <= std_logic_vector(resize(unsigned(din_int(1)),adder_dina0'length));
            else -- use the feedback as input for the rest of the adds
               adder_dina0 <= bin0_sum(adder_dina0'length -1 downto 0);
               adder_dinb0 <= std_logic_vector(resize(unsigned(din_int(to_integer(add_count0+1))),adder_dina0'length));
            end if;

            if(ena_int = '1') then
               if(add_count0 = G_LENGTH -2) then
                  add_count0 <= (others=>'0');
                  add0_vld <= '1';
               else
                  add_count0 <= add_count0 + 1;
                  add0_vld <= '0';
               end if;
            else
               add_count0 <= (others=>'0');
               add0_vld <= '0';
            end if;
         end if;
      end if;
   end process;

   c_Bin0_Adder: adder_2input
   generic map(
      -- Pipes
         G_NUM_IN_PIPES       => 0,             -- : natural:=1;     -- Number of input pipelines
         G_NUM_OUT_PIPES      => 0,             -- : natural:=1;     -- Number of output pipelines
         G_USE_RST            => G_USE_RST,     -- : std_logic:='0'; -- '1' use reset logic, '0' remove reset logic
         G_IS_SYNC_RST        => G_IS_SYNC_RST, -- : std_logic:='1'; -- '1' use synchronous reset, '0' use asynchronous reset
         -- Parameters
         G_IS_SIGNED          => '0',           -- : std_logic:='0'; -- '1' inputs/outputs are signed binary, '0' inputs/outputs are unsigned binary
         G_IS_SUBTRATCTION    => '0'            -- : std_logic:='0'  -- '1' Add, '0' subtract
   )
   port map ( 
         CLK                  => CLK,           -- : in std_logic;-- System Clock
         RST                  => RST,           -- : in std_logic;-- Synchronous Reset

         DINA                 => adder_dina0,   -- : in std_logic_vector(0 downto 0);  -- First Data Input
         DINB                 => adder_dinb0,   -- : in std_logic_vector(0 downto 0);  -- Second Data Input

         DOUT                 => bin0_sum       -- : out std_logic_vector(1 downto 0)  -- Data Output
   ); --adder_2input;

   comp_Barret_Bin0: barret_reduction
   generic map(
      G_USE_STATIC_MODULUS       => G_USE_STATIC_MODULUS,-- : std_logic:='1'; -- '1' use generics for reductions, '0' use ports for reductions
      G_NUM_IN_PIPES             =>  1,                  -- : natural:=1; -- Number of pipelines on all inputs
      G_NUM_OUT_PIPES            =>  1,                  -- : natural:=1; -- Number of pipelines on all outputs
      G_USE_RST                  => '0',                 -- : std_logic:='0'; -- '1' enable SRST port, '0' disable SRST port
      G_IS_SYNC_RST              => '1',                 -- : std_logic:='1'; -- '1' use synchronous reset, '0' use asychronous reset
   -- Static or Dynamic modulus  
      G_R                        => G_R,                 -- : std_logic_vector:=x"1"; -- R multiplier for x*R
      G_K2                       => G_K2,                -- : std_logic_vector:=x"1"; -- Divider for x*r/4*k
      G_MODULUS                  => G_MODULUS,           -- : std_logic_vector:=x"3"; -- Modulus for reduction
   -- Tweaking Pipelines  
      G_NUM_RMULT_IN_PIPES       => 2,                   -- : natural:=2; -- Number of pipelines on input of R multiplier
      G_NUM_RMULT_OUT_PIPES      => 3,                   -- : natural:=3; -- Number of pipelines on output of R multiplier
      G_NUM_MODMULT_IN_PIPES     => 2,                   -- : natural:=2; -- Number of pipelines on input of Modulus multiplier
      G_NUM_MODMULT_OUT_PIPES    => 3,                   -- : natural:=3; -- Number of pipelines on output of Modulus multiplier
      G_NUM_TSUB_PIPES           => 0                    -- : natural:=0  -- Number of pipelines on output of t divider
   )
   port map(
      CLK             => CLK,                            -- : in std_logic;
      RST             => RST,                            -- : in std_logic;
   -- Config
      R               => R,                              -- : in std_logic_vector(15 downto 0);
      K2              => K2,                             -- : in std_logic_vector(15 downto 0); 
      MODULUS         => MODULUS,                        -- : in std_logic_vector(15 downto 0); 
      
      DIN             => bin0_sum,                       -- : in std_logic_vector(15 downto 0);
      ENA             => add0_vld,                       -- : in std_logic;
      DOUT            => bin0,                           -- : out std_logic_vector
      VLD             => bin0_vld                        -- : out std_logic
   ); -- barret_reduction;
   
   pipe_bin0_Delay : pipe generic map(G_RANK => 4,G_IS_DELAY => "TRUE", G_USE_RST => G_USE_RST, G_IS_SYNC_RST => G_IS_SYNC_RST) 
   port map(CLK => CLK,RST => RST, D => bin0, Q => DOUT(0));
   
----------------------------------------------
-- Other Bins
-- Desc: Bins require both multiplication and addition
----------------------------------------------   
   gen_bin_mult: for i in 0 to G_LENGTH-1 generate
   gen_bin_mult: for j in 0 to G_LENGTH-1 generate
      comp_bin: multiplier
      generic map(
          G_IN_PIPES         => 2,                             -- : natural:= 2;    -- Pipe delays on A and B. 
          G_OUT_PIPES        => 2,                             -- : natural:= 2;    -- Pipe delays on P_OUT
          G_USE_RST          => G_USE_RST,                     -- : std_logic:='0'; -- '1' enable resets, '0' disable resets
          G_IS_SYNC_RST      => G_IS_SYNC_RST,                 -- : std_logic:='1'; -- '1' use synchronous reset, '0' use asynchronous reset
          G_A_IS_SIGNED      => '0',                           -- : std_logic:='0'; -- '1' A_IN is signed, '0' A_IN is unsigned
          G_B_IS_SIGNED      => '0'                            -- : std_logic:='0'  -- '1' B_IN is signed, '0' B_IN is unsigned
      )
      port map(
          CLK                => CLK,                           -- : in  std_logic;
          RST                => RST,                           -- : in  std_logic;
   
          A_IN               => root_array(i*j mod integer(G_LENGTH)), -- : in  std_logic_vector; -- A Input
          B_IN               => din_int(i),                    -- : in  std_logic_vector; -- B Input
          P_OUT              => bin_mult_dout(i)(j)            -- : out std_logic_vector  -- A*B output, A_IN'len + B_IN'len - 1 downto 0)
      );

    end generate;
    end generate;
    
    -- Create valid signal based of the total delay of the block
   pipe_mult_vld : pipe generic map(G_RANK => 4, G_IS_DELAY => "TRUE", G_USE_RST => G_USE_RST, G_IS_SYNC_RST => G_IS_SYNC_RST)
   port map(CLK => CLK,RST => RST, D(0) => ena_int, Q(0) => vld_mult_int);

   p_Adder_Reuse1: process(CLK)
   begin
      for i in 0 to G_LENGTH-2 loop
         if(G_USE_RST = '1' and G_IS_SYNC_RST = '0' and RST = '1') then
            add_count <= (others=>'0');
            adder_dina(i) <= (others=>'0');
            adder_dinb(i) <= (others=>'0');
            add_vld <= '0';
         elsif(rising_edge(CLK)) then
            if(G_USE_RST = '1' and G_IS_SYNC_RST = '1' and RST = '1') then
               add_count <= (others=>'0');
               adder_dina(i) <= (others=>'0');
               adder_dinb(i) <= (others=>'0');
               add_vld <= '0';
            else
               -- if it's the first add, you do not use the feedback as input
               if(add_count = C_ZEROS) then
                  adder_dina(i) <= std_logic_vector(resize(unsigned(bin_mult_dout(0)(i+1)),adder_dina(i)'length));
                  adder_dinb(i) <= std_logic_vector(resize(unsigned(bin_mult_dout(1)(i+1)),adder_dina(i)'length));
               else -- use the feedback as input for the rest of the adds
                  adder_dina(i) <= bin_sum(i)(adder_dina(i)'length -1 downto 0);
                  adder_dinb(i) <= std_logic_vector(resize(unsigned(bin_mult_dout(to_integer(add_count+1))(i+1)),adder_dina(i)'length));
               end if;
   
                  if(vld_mult_int = '1') then
                     if(add_count = G_LENGTH -2) then
                        add_count <= (others=>'0');
                        add_vld <= '1';
                     else
                        add_count <= add_count + 1;
                        add_vld <= '0';
                     end if;
                  else
                     add_count <= (others=>'0');
                     add_vld <= '0';
                  end if;
               end if;
         end if;
      end loop;
   end process;


   gen_bin_add: for i in 0 to G_LENGTH-2 generate
      c_Bin_Adder: adder_2input
      generic map(
         -- Pipes
         G_NUM_IN_PIPES       => 0,             -- : natural:=1;     -- Number of input pipelines
         G_NUM_OUT_PIPES      => 0,             -- : natural:=1;     -- Number of output pipelines
         G_USE_RST            => G_USE_RST,     -- : std_logic:='0'; -- '1' use reset logic, '0' remove reset logic
         G_IS_SYNC_RST        => G_IS_SYNC_RST, -- : std_logic:='1'; -- '1' use synchronous reset, '0' use asynchronous reset
         -- Parameters
         G_IS_SIGNED          => '0',           -- : std_logic:='0'; -- '1' inputs/outputs are signed binary, '0' inputs/outputs are unsigned binary
         G_IS_SUBTRATCTION    => '0'            -- : std_logic:='0'  -- '1' Add, '0' subtract
      )
      port map ( 
         CLK                  => CLK,           -- : in std_logic;-- System Clock
         RST                  => RST,           -- : in std_logic;-- Synchronous Reset

         DINA                 => adder_dina(i), -- : in std_logic_vector(0 downto 0);  -- First Data Input
         DINB                 => adder_dinb(i), -- : in std_logic_vector(0 downto 0);  -- Second Data Input

         DOUT                 => bin_sum(i)     -- : out std_logic_vector(1 downto 0)  -- Data Output

      ); --adder_2input;
   end generate gen_bin_add;

   gen_bin_barret: for i in 0 to G_LENGTH-2 generate
      comp_Barret_Bin0: barret_reduction
      generic map(
         G_USE_STATIC_MODULUS       => G_USE_STATIC_MODULUS, -- : std_logic:='1'; -- '1' use generics for reductions, '0' use ports for reductions
         G_NUM_IN_PIPES             =>  1,                   -- : natural:=1; -- Number of pipelines on all inputs
         G_NUM_OUT_PIPES            =>  1,                   -- : natural:=1; -- Number of pipelines on all outputs
         G_USE_RST                  => G_USE_RST,            -- : std_logic:='0'; -- '1' enable SRST port, '0' disable SRST port
         G_IS_SYNC_RST              => G_IS_SYNC_RST,        -- : std_logic:='1'; -- '1' use synchronous reset, '0' use asychronous reset
      -- Static or Dynamic modulus  
         G_R                        => G_R,                  -- : std_logic_vector:=x"1"; -- R multiplier for x*R
         G_K2                       => G_K2,                 -- : std_logic_vector:=x"1"; -- Divider for x*r/4*k
         G_MODULUS                  => G_MODULUS,            -- : std_logic_vector:=x"3"; -- Modulus for reduction
      -- Tweaking Pipelines  
         G_NUM_RMULT_IN_PIPES       => 2,        -- : natural:=2; -- Number of pipelines on input of R multiplier
         G_NUM_RMULT_OUT_PIPES      => 3,        -- : natural:=3; -- Number of pipelines on output of R multiplier
         G_NUM_MODMULT_IN_PIPES     => 2,        -- : natural:=2; -- Number of pipelines on input of Modulus multiplier
         G_NUM_MODMULT_OUT_PIPES    => 3,        -- : natural:=3; -- Number of pipelines on output of Modulus multiplier
         G_NUM_TSUB_PIPES           => 0         -- : natural:=0  -- Number of pipelines on output of t divider
      )
      port map(
         CLK             => CLK,                 -- : in std_logic;
         RST             => RST,                 -- : in std_logic;
      -- Config
         R               => R,                   -- : in std_logic_vector(15 downto 0);
         K2              => K2,                  -- : in std_logic_vector(15 downto 0); 
         MODULUS         => MODULUS,             -- : in std_logic_vector(15 downto 0); 
         
         DIN             => bin_sum(i),          -- : in std_logic_vector(15 downto 0);
         ENA             => add_vld,             -- : in std_logic;
         DOUT            => DOUT(i+1),              -- : out std_logic_vector
         VLD             => VLD              -- : out std_logic
      ); -- barret_reduction;
   end generate gen_bin_barret;

end behavioral;
