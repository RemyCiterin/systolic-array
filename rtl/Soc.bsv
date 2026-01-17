//import SystolicMxM :: *;
import Fifo :: *;
import Ehr :: *;

import Accel::*;
import AccelInstr::*;
import ClientServer :: *;
import StmtFSM :: *;
import GetPut :: *;

import SystolicF8 :: *;

import Vector :: *;
import BuildVector :: *;

interface SocIfc;
endinterface

(* synthesize *)
module mkSoc(SocIfc);
endmodule

(* synthesize *)
module mkSocSim(Empty);
  mkSystolicTB;
  //let accel <- mkAccelerator;

  //mkAutoFSM(seq
  //  accel.put(Instr{
  //    opcode: Load,
  //    immediate: 0,
  //    xdst: Range{start: 0, stop: 1},
  //    xsrc: ?, ydst: ?, ysrc: ?
  //  });

  //  action
  //    let a <- accel.rdport.request.get;
  //    $display(fshow(a));
  //  endaction

  //  accel.rdport.response.put(pack('h00112233));

  //  action
  //    let a <- accel.rdport.request.get;
  //    $display(fshow(a));
  //  endaction

  //  accel.rdport.response.put(pack('h00112533));

  //  action
  //    $display("Send request");
  //    accel.put(Instr{
  //      opcode: Store,
  //      immediate: 0,
  //      xsrc: Range{start: 0, stop: 1},
  //      xdst: ?, ydst: ?, ysrc: ?
  //    });
  //  endaction

  //  action
  //    let a <- accel.wrport.request.get;
  //    $display(fshow(a));
  //  endaction

  //  action
  //    let a <- accel.wrport.request.get;
  //    $display(fshow(a));
  //  endaction

  //endseq);
endmodule
