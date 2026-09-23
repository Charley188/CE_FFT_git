# Vivado file properties: USED_IN_SYNTHESIS=false,
# USED_IN_IMPLEMENTATION=true, PROCESSING_ORDER=LATE.
# Apply after linking the BD netlist and reading its scoped IP constraints.
# This unused QSPI input register has no external IO connection.
set_property IOB FALSE [get_cells -hierarchical -filter {NAME == design_1_wrapper_inst/design_1_i/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/IO0_I_REG}]
