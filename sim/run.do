vlib        work

vlog        -sv                                 \
            +define+MULTI_CPL                   \
            ./tb/pcie_ut_tb.sv


vlog +define+SIM_ON  ../code/pcie_user_if/*.v
vlog +define+SIM_ON  ../code/pcie_user_top/*.v


#log–≈œ¢
transcript file error.log


vsim -voptargs=+acc -L unisims_ver -L xpm \
     work.pcie_ut_tb glbl


log -r /*

do wave.do

run 20us

