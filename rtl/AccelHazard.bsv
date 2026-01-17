import AccelInstr :: *;
import Vector :: *;
import Fifo :: *;
import Ehr :: *;


// Ensure their is no "hazard" in the pipeline, two kind of hazard has to be checked:
// - read-after-write: an instruction must read a register, but the register is not available
//    because it's value is being computed by a previous instruction, their is a data depedency
//    between the two instructions
// - write-after-write: an instruction must write a register, but the register is not available
//    because it's value is being computed by a previous instruction, as the values can be
//    write-back out of order we don't authorize this pattern
interface HazardQueue#(numeric type n, type r);
  method Action complete(Range#(r) range);
  method Bool search(Range#(r) register);
  method Action push(Range#(r) range);
endinterface

module mkHazardQueue(HazardQueue#(n, r)) provisos(Bits#(r, rW), Ord#(r), Eq#(r));
  Vector#(n, Reg#(Range#(r))) entries <- replicateM(mkRegU);
  Reg#(Bit#(TLog#(n))) head <- mkReg(0);
  Ehr#(2, Bit#(n)) valid <- mkEhr(0);

  Fifo#(2, Range#(r)) completeQ <- mkFifo;

  rule complete_rl;
    let range = completeQ.first;
    Bit#(n) tmp = valid[0];

    for (Integer i=0; i < valueOf(n); i = i + 1) begin
      if (entries[i] == range) tmp[i] = 0;
    end

    valid[0] <= tmp;
    completeQ.deq;
  endrule

  method Bool search(Range#(r) range);
    Bool found = False;

    for (Integer i=0; i < valueOf(n); i = i + 1) begin
      if (valid[1][i] == 1 && intersectRange(range, entries[i])) found = True;
    end

    return found;
  endmethod

  method Action push(Range#(r) range) if (valid[1][head] == 0);
    entries[head] <= range;
    valid[1][head] <= 1;
    head <= head + 1;
  endmethod

  method Action complete(Range#(r) range);
    completeQ.enq(range);
  endmethod
endmodule

(* synthesize *)
module mkXHazardQueue(HazardQueue#(4, XReg));
  let ifc <- mkHazardQueue;
  return ifc;
endmodule

(* synthesize *)
module mkYHazardQueue(HazardQueue#(4, YReg));
  let ifc <- mkHazardQueue;
  return ifc;
endmodule
