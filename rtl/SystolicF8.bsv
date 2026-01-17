// MAC: multiply and accumulate, processing elements of the systolic array
// This version use fifos before and after the array to smooth the difference
// of delays between the different paths inside the MAC array
//
//                  ________      +--------------------------+
// ----------------]________]---> | MAC -> MAC -> MAC -> MAC |
//                                |  |      |      |      |  |
//                  ________      |  v      v      v      v  |
// ----------------]________]---> | MAC -> MAC -> MAC -> MAC |
//                                |  |      |      |      |  |
//                  ________      |  v      v      v      v  |
// ----------------]________]---> | MAC -> MAC -> MAC -> MAC |
//                                |  |      |      |      |  |
//                  ________      |  v      v      v      v  |
// ----------------]________]---> | MAC -> MAC -> MAC -> MAC |
//                                +--------------------------+
//                                   |      |      |      |
//                                  |_|    |_|    |_|    |_|
//                                  | |    | |    | |    | |
//                                  | |    | |    | |    | |
//                                  | |    | |    | |    | |
//                                  |_|    |_|    |_|    |_|
//                                   |      |      |      |
//                                   |      |      |      |
//                                   |      |      |      |
//                                   v      v      v      v

import FloatingPoint :: *;
import ClientServer :: *;
import BuildVector :: *;
import StmtFSM :: *;
import GetPut :: *;
import Vector::*;
import Fifo :: *;
import Ehr :: *;

// export SystolicNxN(..);
// export mkSystolicNxN;
// export mkSystolicTB;

typedef FloatingPoint#(4, 3) F8;

// Type of data that flow into the pipeline
typedef struct {
  // Value of the neuron or the weight
  F8 data;

  // In case of a weight: row the weight must be stored
  Bit#(TLog#(n)) row;

  // Is the data a weight or a neuron
  Bool isWeight;
} PipInput#(numeric type n) deriving(Bits);

instance DefaultValue#(PipInput#(n));
  function defaultValue = PipInput{
    isWeight: ?,
    data: ?,
    row: ?
  };
endinstance


RoundMode roundingMode = Rnd_Nearest_Even;

typedef Server#(Tuple4#(Maybe#(F8), F8, F8, RoundMode), Tuple2#(F8, Exception)) FMA;

interface ProcessingElement#(numeric type n);
  method Action receiveLeft(PipInput#(n) in);
  method Action receiveTop(F8 data);

  method ActionValue#(F8) sendBottom;
  method ActionValue#(PipInput#(n)) sendRight;
endinterface

module mkProcessingElement#(Bit#(TLog#(n)) row) (ProcessingElement#(n));
  Server#(Tuple4#(Maybe#(F8), F8, F8, RoundMode), Tuple2#(F8, Exception))
    fma <- mkFloatingPointFusedMultiplyAccumulate;

  Fifo#(1, F8) topQ <- mkPipelineFifo;
  Fifo#(1, PipInput#(n)) leftQ <- mkPipelineFifo;
  Reg#(F8) weight <- mkRegU;

  method receiveLeft = leftQ.enq;
  method receiveTop = topQ.enq;

  method ActionValue#(PipInput#(n)) sendRight;
    if (!leftQ.first.isWeight) begin
      fma.request.put(tuple4(Valid(topQ.first), weight, leftQ.first.data, roundingMode));
      topQ.deq;
    end

    if (leftQ.first.isWeight && leftQ.first.row == row) weight <= leftQ.first.data;

    leftQ.deq;

    return leftQ.first;
  endmethod

  method ActionValue#(F8) sendBottom;
    match {.ret, .*} <- fma.response.get;
    return ret;
  endmethod
endmodule

interface SystolicNxN#(numeric type n);
  method Action put(Bool weight, Bit#(TLog#(n)) row, Vector#(n, F8) data);
  method ActionValue#(Vector#(n, F8)) get;

  method Bool canPut;
  method Bool canGet;
endinterface

module mkSystolicNxN(SystolicNxN#(n));
  Vector#(n, Vector#(n, ProcessingElement#(n))) fma = replicate(newVector);

  Vector#(n, Fifo#(TMul#(10,n), PipInput#(n))) inDelay <- replicateM(mkFifo);
  Vector#(n, Fifo#(TMul#(10,n), F8)) outDelay <- replicateM(mkFifo);

  for (Integer i=0; i < valueOf(n); i = i + 1) begin
    for (Integer j=0; j < valueOf(n); j = j + 1) begin
      fma[i][j] <- mkProcessingElement(fromInteger(j));
    end
  end

  for (Integer i=0; i < valueOf(n); i = i + 1) begin
    for (Integer j=0; j < valueOf(n); j = j + 1) begin
      rule send_bottom;
        let x <- fma[i][j].sendBottom;
        if (i == valueof(n) - 1) outDelay[j].enq(x);
        else fma[i+1][j].receiveTop(x);
      endrule

      rule send_right;
        let x <- fma[i][j].sendRight;
        if (j != valueof(n) - 1) fma[i][j+1].receiveLeft(x);
      endrule
    end

    rule receive_left;
      fma[i][0].receiveLeft(inDelay[i].first);
      inDelay[i].deq;
    endrule

    rule receive_top;
      fma[0][i].receiveTop(0);
    endrule
  end

  Bool putReady = True;
  Bool getReady = True;
  for (Integer i=0; i < valueOf(n); i = i + 1) begin
    putReady = putReady && inDelay[i].canEnq;
    getReady = getReady && outDelay[i].canDeq;
  end

  method Bool canPut = putReady;

  method Action put(Bool isWeight, Bit#(TLog#(n)) row, Vector#(n, F8) data);
    for (Integer i=0; i < valueof(n); i = i + 1) begin
      inDelay[i].enq(PipInput{isWeight: isWeight, data: data[i], row: row});
    end
  endmethod

  method Bool canGet = getReady;

  method ActionValue#(Vector#(n, F8)) get;
    Vector#(n, F8) ret = newVector;

    for (Integer i=0; i < valueof(n); i = i + 1) begin
      ret[i] = outDelay[i].first;
      outDelay[i].deq;
    end

    return ret;
  endmethod
endmodule

module mkSystolicTB(Bit#(8));
  let mult <- mkSystolic4x4;

  Reg#(Bit#(32)) cycle <- mkReg(0);

  Reg#(Bit#(8)) led <- mkReg(0);

  Reg#(Bit#(32)) value <- mkRegU;

  rule incrCycle;
    cycle <= cycle + 1;
  endrule

  function sum(x,y) = x+y;

  let fsm = seq
    // Send a matrix `A` in the systolic array in `n` cycles
    mult.put(True, 0, vec(1, 0, 0, 0));
    mult.put(True, 1, vec(0, 1, 0, 0));
    mult.put(True, 2, vec(0, 0, 1, 0));
    mult.put(True, 3, vec(0, 0, 0, 1));

    // Send two vectors `X` to compute `A x X` in one cycle each, `2n+2` cycles of latency
    mult.put(False, ?, vec(9, 7, 1, 4));
    mult.put(False, ?, vec(5, 2, 1, 4));

    action
      let x <- mult.get;
      $display(cycle, " x: ", fshow(x), " ", fshow(Vector#(4,F8)'(vec(9, 7, 1, 4))));
    endaction

    action
      let x <- mult.get;
      $display(cycle, " x: ", fshow(x), " ", fshow(Vector#(4,F8)'(vec(5, 2, 1, 4))));
    endaction
  endseq;

  mkAutoFSM(fsm);

  return led;

endmodule

(* synthesize *)
module mkSystolic2x2(SystolicNxN#(2));
  let ifc <- mkSystolicNxN;
  return ifc;
endmodule

(* synthesize *)
module mkSystolic4x4(SystolicNxN#(4));
  let ifc <- mkSystolicNxN;
  return ifc;
endmodule

//(* synthesize *)
//module mkSystolic8x8(SystolicNxN#(8));
//  let ifc <- mkSystolicNxN;
//  return ifc;
//endmodule
