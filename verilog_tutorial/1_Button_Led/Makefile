PROJ = button_led
DEVICE = lp8k
SOURCES = $(PROJ).v
PIN_DEF = pins.pcf

all: $(PROJ).rpt $(PROJ).bin 

png: $(PROJ).png

%.blif: $(SOURCES)
	yosys -p 'synth_ice40 -top $(PROJ) -blif $@' $^

%.png: %.v
	#yosys -p 'synth; clean; show -format png -prefix ys_$*' $^
	yosys -p 'synth_ice40; clean; show -format png -prefix ys_$*_ice40' $^
	rm -f *.dot

%.asc: $(PIN_DEF) %.blif
	arachne-pnr -s 7 -d 8k -P cm81 -o $@ -p $^

%.bin: %.asc
	icepack $< $@

%.rpt: %.asc
	icetime -d $(DEVICE) -mtr $@ $<

%_tb: %_tb.v %.v
	iverilog -o $@ $^

%_tb.vcd: %_tb
	vvp -N $< +vcd=$@

%_syn.v: %.blif
	yosys -p 'read_blif -wideports $^; write_verilog $@'

%_syntb: %_tb.v %_syn.v
	iverilog -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v`

%_syntb.vcd: %_syntb
	vvp -N $< +vcd=$@

prog: $(PROJ).bin
	prog_fpga.py $<

sudo-prog: $(PROJ).bin
	@echo 'Executing prog as root!!!'
	sudo tinyprog -p $<

clean:
	rm -f a.out *.blif *.asc *.rpt *.bin *.png *.dot

.SECONDARY:
.PHONY: all prog clean
