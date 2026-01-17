import ClientServer :: *;
import SystolicNxN :: *;
import Arbiter :: *;
import GetPut :: *;
import Fifo :: *;
import Ehr :: *;

import AccelInstr::*;
import AccelRegisterFile :: *;

import AccelHazard :: *;

import Vector :: *;

import BRAMCore :: *;

interface Accelerator;
  interface Client#(Bit#(32), Bit#(TMul#(Width, 8))) rdport;
  interface Client#(Tuple2#(Bit#(32), Bit#(TMul#(Width, 8))), void) wrport;
  method Action put(Instr instr);
endinterface

(* synthesize *)
module mkAccelerator(Accelerator);
  // SystolicNxN#(Width) multiplier <- mkSystolicNxN;

  let xrf <- mkXRegisterFile;
  let yrf <- mkYRegisterFile;

  let queueX <- mkXHazardQueue;
  let queueY <- mkYHazardQueue;

  let dma <- mkDMA(
    actionvalue
      xrf.ack;
      return xrf.data;
    endactionvalue,
    xrf.write
  );

  Fifo#(2, Instr) dispatchQ <- mkFifo;

  rule dispatch_instr;
    let instr = dispatchQ.first;

    if (instr.opcode == Load || instr.opcode == Store) begin
      if (instr.opcode == Load) queueX.push(instr.xdst);
      else xrf.read(instr.xsrc);
      dma.request(instr);
    end

    if (instr.opcode == MultiplySet) begin
      xrf.read(instr.xsrc);
    end

    dispatchQ.deq;
  endrule

  rule dmaComplete;
    let range <- dma.complete;
    queueX.complete(range);
  endrule

  method Action put(Instr instr);
    dispatchQ.enq(instr);
  endmethod

  interface rdport = dma.rdport;
  interface wrport = dma.wrport;
endmodule


interface DMA;
  interface Client#(Bit#(32), Bit#(TMul#(Width, 8))) rdport;
  interface Client#(Tuple2#(Bit#(32), Bit#(TMul#(Width, 8))), void) wrport;
  method ActionValue#(XRange) complete;
  method Action request(Instr instr);
endinterface

// TODO: optimize it to have multiple inflight load and store operations
module mkDMA#(
  ActionValue#(ScVec) getReg,
  function Action wrPort(XReg xreg, ScVec v)
) (DMA);
  Fifo#(2, Bit#(TMul#(Width, 8))) responseQ <- mkFifo;

  Reg#(Bool) idle <- mkReg(True);

  Reg#(Bit#(32)) address <- mkRegU;

  Reg#(XReg) receiveStart <- mkRegU;
  Reg#(XReg) receiveStop <- mkRegU;
  Reg#(XReg) sendStart <- mkRegU;
  Reg#(XReg) sendStop <- mkRegU;
  Reg#(Instr) instr <- mkRegU;

  Reg#(Bool) finishReceive <- mkRegU;
  Reg#(Bool) finishSend <- mkRegU;

  method ActionValue#(XRange) complete
    if (instr.opcode == Load && !idle && finishReceive && finishSend);
    idle <= True;

    return instr.xdst;
  endmethod

  method Action request(Instr ins) if (idle);
    sendStart <= ins.opcode == Load ? ins.xdst.start : ins.xsrc.start;
    sendStop <= ins.opcode == Load ? ins.xdst.stop : ins.xsrc.stop;
    finishSend <= False;

    receiveStart <= ins.opcode == Load ? ins.xdst.start : ins.xsrc.start;
    receiveStop <= ins.opcode == Load ? ins.xdst.stop : ins.xsrc.stop;
    finishReceive <= False;

    address <= ins.immediate;

    idle <= False;
    instr <= ins;
  endmethod

  interface Client rdport;
    interface Get request;
      method ActionValue#(Bit#(32)) get
        if (instr.opcode == Load && !finishSend);

        address <= address + fromInteger(valueOf(Width));
        finishSend <= sendStart == sendStop;
        sendStart <= sendStart + 1;
        return address;
      endmethod
    endinterface

    interface Put response;
      method Action put(Bit#(TMul#(8,Width)) value);
        wrPort(receiveStart, unpack(value));
        finishReceive <= receiveStart == receiveStop;
        receiveStart <= receiveStart + 1;
      endmethod
    endinterface
  endinterface

  interface Client wrport;
    interface Get request;
      method ActionValue#(Tuple2#(Bit#(32), Bit#(TMul#(8,Width)))) get
        if (instr.opcode == Store && !finishSend);

        address <= address + fromInteger(valueOf(Width));
        finishSend <= sendStart == sendStop;
        sendStart <= sendStart + 1;

        let vec <- getReg;

        return tuple2(address, pack(vec));
      endmethod
    endinterface

    interface Put response;
      method Action put(void _) if (!idle && !finishReceive);
        finishReceive <= receiveStart == receiveStop;
        idle <= receiveStart != receiveStop;
        receiveStart <= receiveStart + 1;
      endmethod
    endinterface
  endinterface
endmodule
