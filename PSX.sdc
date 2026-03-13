derive_pll_clocks
derive_clock_uncertainty

create_generated_clock -name {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -source {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|vco0ph[0]} -divide_by 5 -multiply_by 1 -duty_cycle 50.00 { emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk }

# PLL2 (clk_vid) is asynchronous to all other clock domains.
# sys_top.sdc set_clock_groups does not include PLL2, so we need explicit false paths.
# All PLL outputs (clk_1x=general[0], clk_2x=general[1], clk_3x=general[2]) -> PLL2
set_false_path -from {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} -to {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set_false_path -from {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} -to {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set_false_path -from {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk} -to {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set_false_path -from {FPGA_CLK1_50} -to {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set_false_path -from {FPGA_CLK2_50} -to {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set_false_path -from {FPGA_CLK3_50} -to {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set_false_path -from {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}

# PLL2 -> all other clock domains
set_false_path -from {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set_false_path -from {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
set_false_path -from {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}
set_false_path -from {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set_false_path -from {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}
set_false_path -from {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {FPGA_CLK1_50}
set_false_path -from {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {FPGA_CLK2_50}
set_false_path -from {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -to {FPGA_CLK3_50}

# Quasi-static control signals crossing clk_1x -> clk_vid
# These only change on OSD interaction or region detection, not worth timing
set_false_path -from [get_registers {emu|video_isPal}] -to [get_clocks {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}]
set_false_path -from [get_registers {emu|fast_forward}] -to [get_clocks {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}]
set_false_path -from [get_registers {emu|status[*]}] -to [get_clocks {emu|pll2|pll2_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}]