import AccelInstr :: *;
import BRAMCore :: *;
import Vector :: *;
import Ehr :: *;

// {data, valid, register} < read < write
interface RegisterFile#(type r, type d);
  // Send a read request for a range of registers to the register file,
  // the registers of the specified range will be available from the next
  // cycle, from range.start to range.stop. We can start a new request as
  // soon as we receive range.stop (in the same cycle)
  method Action read(Range#(r) r);

  // Receive the i-th register of the current inflight request
  (* always_ready *) method d data;
  (* always_ready *) method Bool valid;
  (* always_ready *) method r register;
  method Action ack;

  method Action write(r k, d v);
endinterface

module mkBRAMReader(RegisterFile#(Bit#(n), data)) provisos(Bits#(data, dataW));
  Reg#(Maybe#(Bit#(n))) currentIdx <- mkReg(Invalid);
  Ehr#(2, Bool) finish <- mkEhr(True);
  Ehr#(3, Bit#(n)) start <- mkEhr(?);
  Reg#(Bit#(n)) stop <- mkRegU;

  BRAM_DUAL_PORT#(Bit#(n), data) bram <- mkBRAMCore2(2 ** valueOf(n), False);

  rule read_ram;
    bram.a.put(False, start[2], ?);
    currentIdx <= Valid(start[2]);
  endrule

  method Action write(Bit#(n) k, data v);
    bram.b.put(True, k, v);
  endmethod

  method Action read(Range#(Bit#(n)) range) if (finish[1]);
    start[1] <= range.start;
    finish[1] <= False;
    stop <= range.stop;
  endmethod

  method Action ack if (!finish[0] && currentIdx == Valid(start[0]));
    finish[0] <= start[0] == stop;
    start[0] <= start[0] + 1;
  endmethod

  method valid = !finish[0] && currentIdx == Valid(start[0]);
  method register = start[0];
  method data = bram.a.read;
endmodule

(* synthesize *)
module mkXRegisterFile(RegisterFile#(XReg, ScVec));
  let ifc <- mkBRAMReader;
  return ifc;
endmodule

(* synthesize *)
module mkYRegisterFile(RegisterFile#(YReg, AccVec));
  let ifc <- mkBRAMReader;
  return ifc;
endmodule
