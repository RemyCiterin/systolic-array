// [ ]: delay register: ensure that each row of input/ouput arrive at the same cycle
// MAC: multiply and accumulate, processing elements of the systolic array
//
//                                +--------------------------+
// ----------------------> [ ] -> | MAC -> MAC -> MAC -> MAC |
//                                |  |      |      |      |  |
//                                |  v      v      v      v  |
// ---------------> [ ] -> [ ] -> | MAC -> MAC -> MAC -> MAC |
//                                |  |      |      |      |  |
//                                |  v      v      v      v  |
// --------> [ ] -> [ ] -> [ ] -> | MAC -> MAC -> MAC -> MAC |
//                                |  |      |      |      |  |
//                                |  v      v      v      v  |
// -> [ ] -> [ ] -> [ ] -> [ ] -> | MAC -> MAC -> MAC -> MAC |
//                                +--------------------------+
//                                   |      |      |      |
//                                   v      v      v      v
//                                  [ ]    [ ]    [ ]    [ ]
//                                   |      |      |      |
//                                   v      v      v      |
//                                  [ ]    [ ]    [ ]     |
//                                   |      |      |      |
//                                   v      v      |      |
//                                  [ ]    [ ]     |      |
//                                   |      |      |      |
//                                   v      |      |      |
//                                  [ ]     |      |      |
//                                   |      |      |      |
//                                   v      v      v      v

import BuildVector :: *;
import StmtFSM :: *;
import Vector::*;
import Ehr :: *;

export SystolicNxN(..);
export mkSystolicNxN;
export mkSystolicTB;

// Type of data that flow into the pipeline
typedef struct {
  // Value of the neuron or the weight
  Bit#(8) data;

  // In case of a weight: row the weight must be stored
  Bit#(TLog#(n)) row;

  // In case of a weight: is the weight signed
  Bool isSigned;

  // Is the data a weight or a neuron
  Bool isWeight;

  // Is the data valid
  Bool valid;
} PipInput#(numeric type n) deriving(Bits);

instance DefaultValue#(PipInput#(n));
  function defaultValue = PipInput{
    valid: False,
    isSigned: ?,
    isWeight: ?,
    data: ?,
    row: ?
  };
endinstance

interface SystolicNxN#(numeric type n);
  method Action put(Bool weight, Bool isSigned, Bit#(TLog#(n)) row, Vector#(n, Bit#(8)) data);
  method ActionValue#(Vector#(n, Bit#(32))) get;

  method Bool canPut;
  method Bool canGet;
endinterface

module mkSystolicNxN(SystolicNxN#(n));
  // Accumulate the output of the systolic array, then flow into delayOut
  Vector#(n, Vector#(n, Reg#(Bit#(32)))) accumulatorData <- replicateM(replicateM(mkRegU));
  Vector#(n, Vector#(n, Reg#(Bool))) accumulatorValid <- replicateM(replicateM(mkReg(False)));

  // Weight of each node of the systolic array
  Vector#(n, Vector#(n, Reg#(Bit#(8)))) weightData <- replicateM(replicateM(mkRegU));

  //Is the weight and the inputs signed ?
  Vector#(n, Vector#(n, Reg#(Bool))) weightSigned <- replicateM(replicateM(mkRegU));

  // Contains the neurons that flow into the systloic array
  Vector#(n, Vector#(n, Reg#(PipInput#(n)))) neurons <- replicateM(replicateM(mkReg(defaultValue)));

  // Input delays
  Vector#(n, List#(Reg#(PipInput#(n)))) delayIn = newVector;
  for (Integer i=0; i < valueOf(n); i = i + 1) begin
    delayIn[i] <- List::replicateM(i+1, mkReg(defaultValue));
  end

  // Output delays
  Vector#(n, List#(Reg#(Bit#(32)))) delayOutData = newVector;
  Vector#(n, List#(Reg#(Bool))) delayOutValid = newVector;
  for (Integer j=0; j < valueOf(n); j = j + 1) begin
    delayOutValid[j] <- List::replicateM(valueOf(n) - j, mkReg(False));
    delayOutData[j] <- List::replicateM(valueOf(n) - j, mkRegU);
  end

  // Input queue
  Vector#(n, Reg#(PipInput#(n))) inputData <- replicateM(mkReg(defaultValue));
  Ehr#(2, Bool) inputValid <- mkEhr(False);

  // Output queue
  Vector#(n, Reg#(Bit#(32))) outputData <- replicateM(mkRegU);
  Ehr#(2, Bool) outputValid <- mkEhr(False);

  // By design all the values in the out delay buffer are valid at the same time, so we choose one
  Bool lastDelayValid = delayOutValid[0][valueOf(n)-1];

  // Stale if both of the ouput queue and output delay buffer are full
  rule step if (!lastDelayValid || !outputValid[1]);

    if (inputValid[0]) inputValid[0] <= False;

    for (Integer i=0; i < valueOf(n); i = i + 1) begin
      // Move values from the input queue to the input delay buffer
      delayIn[i][0] <= inputValid[0] ? inputData[i] : defaultValue;

      // Apply delay to the input
      for (Integer j=0; j < i; j = j + 1) begin
        delayIn[i][j+1] <= delayIn[i][j];
      end

      for (Integer j=0; j < valueOf(n); j = j + 1) begin
        Bool isSigned = weightSigned[i][j];
        PipInput#(n) in = j == 0 ? delayIn[i][i] : neurons[i][j-1];

        Bit#(16) lhs = isSigned ? signExtend(in.data) : zeroExtend(in.data);
        Bit#(16) rhs = isSigned ? signExtend(weightData[i][j]) : zeroExtend(weightData[i][j]);
        Bit#(32) ret = isSigned ? signExtend(lhs * rhs) : zeroExtend(lhs * rhs);

        // Write the output in the accumulator and the current neuron
        accumulatorData[i][j] <= i == 0 ? ret : ret + accumulatorData[i-1][j];
        accumulatorValid[i][j] <= in.valid && !in.isWeight;
        neurons[i][j] <= in;

        // If the input is a weight, then we save it for the next computations
        if (in.valid && in.isWeight && in.row == fromInteger(j)) begin
          weightSigned[i][j] <= in.isSigned;
          weightData[i][j] <= in.data;
        end
      end
    end

    for (Integer j=0; j < valueOf(n); j = j + 1) begin
      delayOutValid[j][0] <= accumulatorValid[valueOf(n)-1][j];
      delayOutData[j][0]  <= accumulatorData[valueOf(n)-1][j];

      for (Integer i=0; i < valueOf(n) - j - 1; i = i + 1) begin
        delayOutValid[j][i+1] <= delayOutValid[j][i];
        delayOutData[j][i+1] <= delayOutData[j][i];
      end

      if (lastDelayValid) outputData[j] <= delayOutData[j][valueOf(n) - j - 1];
    end

    if (lastDelayValid) outputValid[1] <= True;
  endrule

  method Bool canPut = !inputValid[1];

  method Action put(Bool isWeight, Bool isSigned, Bit#(TLog#(n)) row, Vector#(n, Bit#(8)) data)
    if (!inputValid[1]);
    inputValid[1] <= True;

    for (Integer i=0; i < valueOf(n); i = i + 1) begin
      inputData[i] <= PipInput{
        isWeight: isWeight,
        isSigned: isSigned,
        data: data[i],
        valid: True,
        row: row
      };
    end
  endmethod

  method Bool canGet = outputValid[0];

  method ActionValue#(Vector#(n, Bit#(32))) get if (outputValid[0]);
    outputValid[0] <= False;

    return readVReg(outputData);
  endmethod
endmodule

module mkSystolicTB(Bit#(8));
  let mult <- mkSystolic8x8;

  Reg#(Bit#(32)) cycle <- mkReg(0);

  Reg#(Bit#(8)) led <- mkReg(0);

  Reg#(Bit#(32)) value <- mkRegU;

  rule incrCycle;
    cycle <= cycle + 1;
  endrule

  function sum(x,y) = x+y;

  let fsm = seq
    // Send a matrix `A` in the systolic array in `n` cycles
    mult.put(True, True, 0, vec(1, 0, 0, 0, 0, 0, 0, 0));
    mult.put(True, True, 1, vec(0, 1, 0, 0, 0, 0, 0, 0));
    mult.put(True, True, 2, vec(0, 0, 1, 0, 0, 0, 0, 0));
    mult.put(True, True, 3, vec(0, 0, 0, 1, 0, 0, 0, 0));
    mult.put(True, True, 4, vec(0, 0, 0, 0, 1, 0, 0, 0));
    mult.put(True, True, 5, vec(0, 0, 0, 0, 0, 1, 0, 0));
    mult.put(True, True, 6, vec(0, 0, 0, 0, 0, 0, 1, 0));
    mult.put(True, True, 7, vec(0, 0, 0, 0, 0, 0, 0, 1));

    // Send two vectors `X` to compute `A x X` in one cycle each, `2n+2` cycles of latency
    mult.put(False, ?, ?, vec(9, 7, 1, 4, 3, 1, 8, 6));
    mult.put(False, ?, ?, vec(5, 2, 1, 4, 4, 7, 8, 0));

    action
      let x <- mult.get;
      $display(cycle, " x: ", fshow(x));
      value <= foldr(sum, 0, x);
    endaction

    led <= value[7:0] + value[15:8] + value[23:16] + value[31:24];

    action
      let x <- mult.get;
      $display(cycle, " x: ", fshow(x));
      value <= foldr(sum, 0, x);
    endaction

    led <= value[7:0] + value[15:8] + value[23:16] + value[31:24];
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

(* synthesize *)
module mkSystolic8x8(SystolicNxN#(8));
  let ifc <- mkSystolicNxN;
  return ifc;
endmodule
