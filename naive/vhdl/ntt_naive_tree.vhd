-- Title: Naive Number Theoretic Transform
-- Created by: Cody Emerson
-- Date: 9/08/2021
-- Target: Xilinx Ultrascale
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
-- Description: Perform the Number Theoretic Transform according
-- to the dictionary definition with a tree structure for the additions
--|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use ieee.std_logic_unsigned.all;
use ieee.numeric_std_unsigned.all; 

library work;
use work.helper_functions.all;

entity ntt_naive_tree is
   generic(
      G_NUM_IN_PIPES               : natural:=1;      -- Number of pipelines on all inputs
      G_NUM_OUT_PIPES              : natural:=1;      -- Number of pipelines on all outputs
      G_USE_RST                    : std_logic:='0';  -- '1' enable SRST port, '0' disable SRST port
      G_IS_SYNC_RST                : std_logic:='1';  -- '1' use synchronous reset, '0' use asynchronous reset
      G_USE_STATIC_MODULUS         : std_logic:= '1'; -- '1' Parameters are generics, '0' parameters are ports
      G_GENERATOR                  : positive:=2;     
      G_R                          : std_logic_vector:=x"9";
      G_K2                         : std_logic_vector:="110";
      G_MODULUS                    : std_logic_vector:="111";
      G_LENGTH                     : positive:=2;
   -- Pipelines
      G_MULT_IN_PIPES              : natural:=2;
      G_MULT_OUT_PIPES             : natural:=2;
      G_ADDER_IN_PIPES             : natural:=1;
      G_ADDER_OUT_PIPES            : natural:=1;
      G_REDUCT_IN_PIPES            : natural:=1;
      G_REDUCT_RMULT_IN_PIPES      : natural:=2;
      G_REDUCT_RMULT_OUT_PIPES     : natural:=3;
      G_REDUCT_MODMULT_IN_PIPES    : natural:=2;
      G_REDUCT_MODMULT_OUT_PIPES   : natural:=3;
      G_REDUCT_TSUB_PIPES          : natural:=0 
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
end ntt_naive_tree;

architecture behavioral of ntt_naive_tree is 

-- Functions
   -- For a static modulus, calculate the roots locally
   function f_calculate_roots return std_logic_array is
      variable var_out_array : std_logic_array(G_LENGTH*2 downto 0)(G_MODULUS'length-1 downto 0);
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
   constant C_ZEROS      : unsigned(G_LENGTH-1 downto 0):=(others=>'0');
   constant C_VLD_PIPES0 : natural:=G_NUM_IN_PIPES + G_NUM_OUT_PIPES + G_MULT_IN_PIPES + G_MULT_OUT_PIPES + G_ADDER_IN_PIPES*2 + G_ADDER_OUT_PIPES*2;
   constant C_VLD_PIPES1 : natural:=C_VLD_PIPES0 + G_REDUCT_IN_PIPES + G_REDUCT_RMULT_IN_PIPES + G_REDUCT_RMULT_OUT_PIPES + G_REDUCT_MODMULT_IN_PIPES + G_REDUCT_MODMULT_OUT_PIPES + G_REDUCT_TSUB_PIPES;

-- Signals
 -- Inputs
   signal root_array  : std_logic_array(G_LENGTH*2 downto 0)(G_MODULUS'length-1 downto 0);
   signal din_int     : std_logic_array(G_LENGTH -1 downto 0)(G_MODULUS'range); -- Input flops
   signal ena_int     : std_logic;                 -- Input flops  
 -- Multiplier
   signal mult_result       : std_logic_matrix(G_LENGTH-1 downto 0)(G_LENGTH-1 downto 0)(G_MODULUS'length*2-1 downto 0);
   signal mult_result_delay : std_logic_matrix(G_LENGTH-1 downto 0)(G_LENGTH-1 downto 0)(G_MODULUS'length*2-1 downto 0);
   signal bin0_delay        : std_logic_array(G_LENGTH-1 downto 0)(G_MODULUS'length*2-1 downto 0);
 -- Bin 0 Adders
   signal bin0_add0   : std_logic_vector(mult_result(0)(0)'length downto 0);
   signal bin0_add1   : std_logic_vector(bin0_add0'length downto 0);
 -- Bin 1 Adders
   signal bin1_add0   : std_logic_vector(mult_result(0)(0)'length downto 0);
   signal bin1_add1   : std_logic_vector(bin0_add0'length downto 0);
 -- Bin 2 Adders
   signal bin2_add0   : std_logic_vector(mult_result(0)(0)'length downto 0);
   signal bin2_add1   : std_logic_vector(bin0_add0'length downto 0);
 -- Combined Add Results
   signal adder_result : std_logic_array(G_LENGTH-1 downto 0)(bin0_add0'length downto 0);

begin
----------------------------------------------
-- Input Pipelines
-- Desc: Optional Input Pipelining
----------------------------------------------  
   pipe_ENA:  pipe generic map(G_RANK => C_VLD_PIPES1, G_USE_RST => G_USE_RST, G_IS_SYNC_RST => G_IS_SYNC_RST) 
   port map(CLK => CLK,RST => RST,D(0) => ENA , Q(0) => VLD);
   
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
-- Calculate all root*dins
-- Desc: Calculate all multiplications first
----------------------------------------------     
gen_Bin0: for i in 0 to G_LENGTH-1 generate
   mult_result(i)(0) <= std_logic_vector(resize(unsigned(din_int(i)),G_MODULUS'length*2));

   pipe_Bin0_Delay: pipe generic map(G_RANK => G_MULT_IN_PIPES + G_MULT_OUT_PIPES, G_USE_RST => G_USE_RST, G_IS_SYNC_RST => G_IS_SYNC_RST) 
   port map(CLK => CLK,RST => RST,D => mult_result(i)(0) , Q => bin0_delay(i)); 

   pipe_Mult_Result: pipe generic map(G_RANK => G_ADDER_IN_PIPES + G_ADDER_OUT_PIPES, G_USE_RST => G_USE_RST, G_IS_SYNC_RST => G_IS_SYNC_RST) 
   port map(CLK => CLK,RST => RST,D => bin0_delay(i) , Q => mult_result_delay(i)(0)); 
end generate gen_Bin0;

gen_Multipliers_Outerloop: for i in 0 to G_LENGTH -1 generate
   gen_Multiplier_Innerloop: for j in 1 to G_LENGTH -1 generate  
      comp_Root_Multiplier: multiplier
      generic map(
         G_IN_PIPES      => G_MULT_IN_PIPES ,  -- : natural:= 2;    
         G_OUT_PIPES     => G_MULT_OUT_PIPES,  -- : natural:= 2;    
         G_USE_RST       => G_USE_RST,         -- : std_logic:='0'; 
         G_IS_SYNC_RST   => G_IS_SYNC_RST,     -- : std_logic:='1'; 
         G_A_IS_SIGNED   => '0',               -- : std_logic:='0'; 
         G_B_IS_SIGNED   => '0'                -- : std_logic:='0'  
      )
      port map(
         CLK             => CLK,               -- : in  std_logic;
         RST             => RST,               -- : in  std_logic;

         A_IN            => din_int(i),        -- : in  std_logic_vector; 
         B_IN            => root_array(j),     -- : in  std_logic_vector; 
         P_OUT           => mult_result(i)(j)  -- : out std_logic_vector   
      ); --multiplier;

      pipe_Mult_Result: pipe generic map(G_RANK => G_ADDER_IN_PIPES + G_ADDER_OUT_PIPES, G_USE_RST => G_USE_RST, G_IS_SYNC_RST => G_IS_SYNC_RST) 
      port map(CLK => CLK,RST => RST,D => mult_result(i)(j) , Q => mult_result_delay(i)(j)); 

   end generate gen_Multiplier_Innerloop;
end generate gen_Multipliers_Outerloop;

----------------------------------------------
-- Bin 0 Adders
-- Desc: Adder the mult results for bin0
----------------------------------------------  
   c_Bin0_Adder0: adder_2input
   generic map(
      -- Pipes
         G_NUM_IN_PIPES       => G_ADDER_IN_PIPES , -- : natural:=1;     
         G_NUM_OUT_PIPES      => G_ADDER_OUT_PIPES, -- : natural:=1;     
         G_USE_RST            => G_USE_RST,         -- : std_logic:='0';
         G_IS_SYNC_RST        => G_IS_SYNC_RST,     -- : std_logic:='1'; 
         -- Parameters
         G_IS_SIGNED          => '0',               -- : std_logic:='0';
         G_IS_SUBTRATCTION    => '0'                -- : std_logic:='0'  
   )
   port map ( 
         CLK                  => CLK,               -- : in std_logic;-- System Clock
         RST                  => RST,               -- : in std_logic;-- Synchronous Reset

         DINA                 => bin0_delay(0),     -- : in std_logic_vector(0 downto 0);  -- First Data Input
         DINB                 => bin0_delay(1),     -- : in std_logic_vector(0 downto 0);  -- Second Data Input

         DOUT                 => bin0_add0          -- : out std_logic_vector(1 downto 0)  -- Data Output
   ); --adder_2input;

   c_Bin0_Adder1: adder_2input
   generic map(
      -- Pipes
         G_NUM_IN_PIPES       => G_ADDER_IN_PIPES,        -- : natural:=1;     
         G_NUM_OUT_PIPES      => G_ADDER_OUT_PIPES,       -- : natural:=1;     
         G_USE_RST            => G_USE_RST,               -- : std_logic:='0';
         G_IS_SYNC_RST        => G_IS_SYNC_RST,           -- : std_logic:='1'; 
         -- Parameters
         G_IS_SIGNED          => '0',                     -- : std_logic:='0';
         G_IS_SUBTRATCTION    => '0'                      -- : std_logic:='0'  
   )
   port map ( 
         CLK                  => CLK,                     -- : in std_logic;-- System Clock
         RST                  => RST,                     -- : in std_logic;-- Synchronous Reset

         DINA                 => bin0_add0,               -- : in std_logic_vector(0 downto 0);  -- First Data Input
         DINB                 => mult_result_delay(2)(0), -- : in std_logic_vector(0 downto 0);  -- Second Data Input

         DOUT                 => adder_result(0)          -- : out std_logic_vector(1 downto 0)  -- Data Output
   ); --adder_2input;

----------------------------------------------
-- Bin 1 Adders
-- Desc: Adder the mult results for bin1
----------------------------------------------  
   c_Bin1_Adder0: adder_2input
   generic map(
      -- Pipes
         G_NUM_IN_PIPES       => G_ADDER_IN_PIPES,  -- : natural:=1;     
         G_NUM_OUT_PIPES      => G_ADDER_OUT_PIPES, -- : natural:=1;     
         G_USE_RST            => G_USE_RST,         -- : std_logic:='0';
         G_IS_SYNC_RST        => G_IS_SYNC_RST,     -- : std_logic:='1'; 
         -- Parameters
         G_IS_SIGNED          => '0',               -- : std_logic:='0';
         G_IS_SUBTRATCTION    => '0'                -- : std_logic:='0'  
   )
   port map ( 
         CLK                  => CLK,               -- : in std_logic;-- System Clock
         RST                  => RST,               -- : in std_logic;-- Synchronous Reset

         DINA                 => bin0_delay(0),     -- : in std_logic_vector(0 downto 0);  -- First Data Input
         DINB                 => mult_result(1)(1), -- : in std_logic_vector(0 downto 0);  -- Second Data Input

         DOUT                 => bin1_add0          -- : out std_logic_vector(1 downto 0)  -- Data Output
   ); --adder_2input;

   c_Bin1_Adder1: adder_2input
   generic map(
      -- Pipes
         G_NUM_IN_PIPES       => G_ADDER_IN_PIPES,  -- : natural:=1;     
         G_NUM_OUT_PIPES      => G_ADDER_OUT_PIPES, -- : natural:=1;     
         G_USE_RST            => G_USE_RST,         -- : std_logic:='0';
         G_IS_SYNC_RST        => G_IS_SYNC_RST,     -- : std_logic:='1'; 
         -- Parameters
         G_IS_SIGNED          => '0',               -- : std_logic:='0';
         G_IS_SUBTRATCTION    => '0'                -- : std_logic:='0'  
   )
   port map ( 
         CLK                  => CLK,               -- : in std_logic;-- System Clock
         RST                  => RST,               -- : in std_logic;-- Synchronous Reset

         DINA                 => bin1_add0,         -- : in std_logic_vector(0 downto 0);  -- First Data Input
         DINB                 => mult_result_delay(2)(2), -- : in std_logic_vector(0 downto 0);  -- Second Data Input

         DOUT                 => adder_result(1)    -- : out std_logic_vector(1 downto 0)  -- Data Output
   ); --adder_2input;

----------------------------------------------
-- Bin 2 Adders
-- Desc: Adder the mult results for bin2
----------------------------------------------  
   c_Bin2_Adder0: adder_2input
   generic map(
      -- Pipes
         G_NUM_IN_PIPES       => G_ADDER_IN_PIPES,  -- : natural:=1;     
         G_NUM_OUT_PIPES      => G_ADDER_OUT_PIPES, -- : natural:=1;     
         G_USE_RST            => G_USE_RST,         -- : std_logic:='0';
         G_IS_SYNC_RST        => G_IS_SYNC_RST,     -- : std_logic:='1'; 
         -- Parameters
         G_IS_SIGNED          => '0',               -- : std_logic:='0';
         G_IS_SUBTRATCTION    => '0'                -- : std_logic:='0'  
   )
   port map ( 
         CLK                  => CLK,               -- : in std_logic;-- System Clock
         RST                  => RST,               -- : in std_logic;-- Synchronous Reset

         DINA                 => bin0_delay(0),     -- : in std_logic_vector(0 downto 0);  -- First Data Input
         DINB                 => mult_result(1)(2), -- : in std_logic_vector(0 downto 0);  -- Second Data Input

         DOUT                 => bin2_add0          -- : out std_logic_vector(1 downto 0)  -- Data Output
   ); --adder_2input;

   c_Bin2_Adder1: adder_2input
   generic map(
      -- Pipes
         G_NUM_IN_PIPES       => G_ADDER_IN_PIPES,  -- : natural:=1;     
         G_NUM_OUT_PIPES      => G_ADDER_OUT_PIPES, -- : natural:=1;     
         G_USE_RST            => G_USE_RST,         -- : std_logic:='0';
         G_IS_SYNC_RST        => G_IS_SYNC_RST,     -- : std_logic:='1'; 
         -- Parameters
         G_IS_SIGNED          => '0',               -- : std_logic:='0';
         G_IS_SUBTRATCTION    => '0'                -- : std_logic:='0'  
   )
   port map ( 
         CLK                  => CLK,               -- : in std_logic;-- System Clock
         RST                  => RST,               -- : in std_logic;-- Synchronous Reset

         DINA                 => bin2_add0,         -- : in std_logic_vector(0 downto 0);  -- First Data Input
         DINB                 => mult_result_delay(2)(1), -- : in std_logic_vector(0 downto 0);  -- Second Data Input

         DOUT                 => adder_result(2)    -- : out std_logic_vector(1 downto 0)  -- Data Output
   ); --adder_2input;

----------------------------------------------
-- Reduction
-- Desc: Reduce the results by the modulus
----------------------------------------------  
gen_Reduction: for i in 0 to G_LENGTH-1 generate
   comp_Reduction: barret_reduction
   generic map(
      G_USE_STATIC_MODULUS       => G_USE_STATIC_MODULUS,         -- : std_logic:='1'; -- '1' use generics for reductions, '0' use ports for reductions
      G_NUM_IN_PIPES             => G_REDUCT_IN_PIPES,            -- : natural:=1; -- Number of pipelines on all inputs
      G_NUM_OUT_PIPES            => G_NUM_OUT_PIPES,              -- : natural:=1; -- Number of pipelines on all outputs
      G_USE_RST                  => G_USE_RST,                    -- : std_logic:='0'; -- '1' enable SRST port, '0' disable SRST port
      G_IS_SYNC_RST              => G_IS_SYNC_RST,                -- : std_logic:='1'; -- '1' use synchronous reset, '0' use asychronous reset
   -- Static or Dynamic modulus  
      G_R                        => G_R,                          -- : std_logic_vector:=x"1"; -- R multiplier for x*R
      G_K2                       => G_K2,                         -- : std_logic_vector:=x"1"; -- Divider for x*r/4*k
      G_MODULUS                  => G_MODULUS,                    -- : std_logic_vector:=x"3"; -- Modulus for reduction
   -- Tweaking Pipelines  
      G_NUM_RMULT_IN_PIPES       => G_REDUCT_RMULT_IN_PIPES,      -- : natural:=2; -- Number of pipelines on input of R multiplier
      G_NUM_RMULT_OUT_PIPES      => G_REDUCT_RMULT_OUT_PIPES,     -- : natural:=3; -- Number of pipelines on output of R multiplier
      G_NUM_MODMULT_IN_PIPES     => G_REDUCT_MODMULT_IN_PIPES,    -- : natural:=2; -- Number of pipelines on input of Modulus multiplier
      G_NUM_MODMULT_OUT_PIPES    => G_REDUCT_MODMULT_OUT_PIPES,   -- : natural:=3; -- Number of pipelines on output of Modulus multiplier
      G_NUM_TSUB_PIPES           => G_REDUCT_TSUB_PIPES           -- : natural:=0  -- Number of pipelines on output of t divider
   )
   port map(
      CLK             => CLK,                                     -- : in std_logic;
      RST             => RST,                                     -- : in std_logic;
   -- Config
      R               => R,                                       -- : in std_logic_vector(15 downto 0);
      K2              => K2,                                      -- : in std_logic_vector(15 downto 0); 
      MODULUS         => MODULUS,                                 -- : in std_logic_vector(15 downto 0); 
   
      DIN             => adder_result(i),                         -- : in std_logic_vector(15 downto 0);
      ENA             => '1',                                     -- : in std_logic;
      DOUT            => DOUT(i),                                 -- : out std_logic_vector
      VLD             => open                                     -- : out std_logic
   ); -- barret_reduction
end generate gen_Reduction;
   

end behavioral;
