import Vector::*;

typedef 4 Width;
typedef 12 SC_LOG_SIZE;
typedef 8 ACC_LOG_SIZE;

typedef Vector#(Width, Bit#(8)) ScVec;
typedef Vector#(Width, Bit#(32)) AccVec;

typedef Bit#(SC_LOG_SIZE) XReg;
typedef Bit#(ACC_LOG_SIZE) YReg;

typedef Range#(XReg) XRange;
typedef Range#(YReg) YRange;

typedef enum {
  Load = 0,
  Store = 1,
  MultiplySet = 2,
  MultiplyAcc = 3,
  WeightsLoad = 4,
  Scale = 5,
  ScaleRelu = 6
} Opcode deriving(Bits, FShow, Eq);

typedef struct {
  Opcode opcode;
  Bit#(32) immediate;
  XRange xdst;
  YRange ydst;
  XRange xsrc;
  YRange ysrc;
} Instr deriving(Bits, FShow);

typedef struct {
  t start;
  t stop;
} Range#(type t) deriving(Bits, FShow, Eq);

function Maybe#(Range#(Bit#(n))) tailRange(Range#(Bit#(n)) range) =
  range.start == range.stop ? Invalid : Valid(Range{start: range.start+1, stop: range.stop});

function Bool intersectRange(Range#(r) r1, Range#(r) r2) provisos(Ord#(r));
  return
    (r1.start <= r2.start && r2.start <= r1.stop) ||
    (r2.start <= r1.start && r1.start <= r2.stop) ||
    (r1.start <= r2.stop && r2.stop <= r1.stop) ||
    (r2.start <= r1.stop && r1.stop <= r2.stop);
endfunction
