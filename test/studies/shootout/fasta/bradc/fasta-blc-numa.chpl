/* The Computer Language Benchmarks Game
   http://benchmarksgame.alioth.debian.org/

   contributed by Brad Chamberlain
   derived from the GNU C version by Аноним Легионов and Jeremy Zerfas
     as well as previous Chapel versions by Casey Battaglino, Kyle Brady,
     and Preston Sahabu.
*/

config const n = 1000,           // the length of the generated strings
             lineLength = 60,    // the number of columns in the output
             blockSize = 1024;   // the parallelization granularity

config param numSockets = 2;

//
// the computational pipeline has 3 distinct stages, so ideally, we'd
// like to use 3 tasks.  However, if the locale can't support that
// much parallelism, we'll use a number of tasks equal to its maximum
// degree of task parallelism to avoid starvation (because we rely on
// busy-waits which could cause deadlocks otherwise).  Since we're
// creating twice as many tasks to stripe them across the NUMA domains
// and ensure that our 3 main tasks are on NUMA domain 0, we'll compute
// the number of numa tasks and then divide that by 2 to get the number
// of actual tasks.
//
config const maxTaskPar = here.maxTaskPar,
             idealTasks = numSockets*3,
             numTasks = if idealTasks > maxTaskPar
                          then min(3, maxTaskPar)
                          else idealTasks / numSockets,
             numNumaTasks = if numTasks*numSockets > maxTaskPar
                              then numTasks
                              else numTasks*numSockets,
             div = if numTasks*numSockets > maxTaskPar then 1 else numSockets;

config const debug = false;

config type randType = uint(32);  // type to use for random numbers

config param IM = 139968,         // parameters for random number generation
             IA = 3877,
             IC = 29573,
             seed: randType = 42;

if debug {
  writeln("idealTasks   = ", idealTasks);
  writeln("numTasks     = ", numTasks);
  writeln("numNumaTasks = ", numNumaTasks);
  writeln("div          = ", div);
  exit(0);
}

//
// Nucleotide definitions
//
enum nucleotide {
  A = ascii("A"), C = ascii("C"), G = ascii("G"), T = ascii("T"),
  a = ascii("a"), c = ascii("c"), g = ascii("g"), t = ascii("t"),
  B = ascii("B"), D = ascii("D"), H = ascii("H"), K = ascii("K"),
  M = ascii("M"), N = ascii("N"), R = ascii("R"), S = ascii("S"),
  V = ascii("V"), W = ascii("W"), Y = ascii("Y")
}
use nucleotide;

//
// Sequence to be repeated
//
const ALU: [0..286] int(8) = [
  G, G, C, C, G, G, G, C, G, C, G, G, T, G, G, C, T, C, A, C,
  G, C, C, T, G, T, A, A, T, C, C, C, A, G, C, A, C, T, T, T,
  G, G, G, A, G, G, C, C, G, A, G, G, C, G, G, G, C, G, G, A,
  T, C, A, C, C, T, G, A, G, G, T, C, A, G, G, A, G, T, T, C,
  G, A, G, A, C, C, A, G, C, C, T, G, G, C, C, A, A, C, A, T,
  G, G, T, G, A, A, A, C, C, C, C, G, T, C, T, C, T, A, C, T,
  A, A, A, A, A, T, A, C, A, A, A, A, A, T, T, A, G, C, C, G,
  G, G, C, G, T, G, G, T, G, G, C, G, C, G, C, G, C, C, T, G,
  T, A, A, T, C, C, C, A, G, C, T, A, C, T, C, G, G, G, A, G,
  G, C, T, G, A, G, G, C, A, G, G, A, G, A, A, T, C, G, C, T,
  T, G, A, A, C, C, C, G, G, G, A, G, G, C, G, G, A, G, G, T,
  T, G, C, A, G, T, G, A, G, C, C, G, A, G, A, T, C, G, C, G,
  C, C, A, C, T, G, C, A, C, T, C, C, A, G, C, C, T, G, G, G,
  C, G, A, C, A, G, A, G, C, G, A, G, A, C, T, C, C, G, T, C,
  T, C, A, A, A, A, A
];

//
// Index aliases for use with (nucleotide, probability) tuples
//
param nucl = 1,
      prob = 2;

//
// Probability tables for sequences to be randomly generated
//
const IUB = [(a, 0.27), (c, 0.12), (g, 0.12), (t, 0.27),
             (B, 0.02), (D, 0.02), (H, 0.02), (K, 0.02),
             (M, 0.02), (N, 0.02), (R, 0.02), (S, 0.02),
             (V, 0.02), (W, 0.02), (Y, 0.02)];

const HomoSapiens = [(a, 0.3029549426680),
                     (c, 0.1979883004921),
                     (g, 0.1975473066391),
                     (t, 0.3015094502008)];


proc main() {
  repeatMake(">ONE Homo sapiens alu\n", ALU, 2*n);
  randomMake(">TWO IUB ambiguity codes\n", IUB, 3*n);
  randomMake(">THREE Homo sapiens frequency\n", HomoSapiens, 5*n);
}

//
// Redefine stdout to use lock-free binary I/O and capture a newline
//
const stdout = openfd(1).writer(kind=iokind.native, locking=false);
param newline = ascii("\n"): int(8);

//
// Repeat sequence "alu" for n characters
//
proc repeatMake(desc, alu, n) {
  stdout.write(desc);

  const r = alu.size,
        s = [i in 0..(r+lineLength)] alu[i % r];

  for i in 0..n by lineLength {
    const lo = i % r + 1,
          len = min(lineLength, n-i);
    stdout.write(s[lo..#len], newline);
  }
}

//
// Output a random sequence of length 'n' using distribution 'a'
//
proc randomMake(desc, nuclInfo, n) {
  stdout.write(desc);

  const numNucls = nuclInfo.size;
  var cumulProb: [1..numNucls] randType;

  // compute the cumulative probabilities of the nucleotides
  var p = 0.0;
  for i in 1..numNucls {
    p += nuclInfo[i](prob);
    cumulProb[i] = 1 + (p*IM):randType;
  }

  var randGo, outGo: [0..#numTasks] atomic int;

  randGo.write(1);
  outGo.write(1);

  /*
  for i in 0..#numTasks {
    randGo[i].write(1);
    outGo[i].write(1);
  }
*/

  coforall itid in 0..#numNumaTasks {
    if itid%div == 0 {
      const tid = itid / div;
    const chunkSize = lineLength*blockSize;
    const nextTask = (tid + 1) % numTasks;

    var line_buff: [0..(lineLength+1)*blockSize-1] int(8);
    var rands: [0..chunkSize] int/*(32)*/;

    for i in 1..n by chunkSize*numTasks align (tid*chunkSize+1) {
      const bytes = min(chunkSize, n-i+1);

      while (randGo[tid].read() != i) do ;
      getRands(bytes, rands);
      randGo[nextTask].write(i + chunkSize);

      var col = 0;
      var off = 0;
      for i in 0..#bytes {
        const r = rands[i];
        var ncnt = 1;
        for j in 1..numNucls do
          if r >= cumulProb[j] then
            ncnt += 1;

        line_buff[off] = nuclInfo[ncnt](nucl);

        off += 1;
        col += 1;
        if (col == lineLength) {
          col = 0;
          line_buff[off] = newline;
          off += 1;
        }
      }
      if (col != 0) {
        line_buff[off] = newline;
        off += 1;
      }

      while (outGo[tid].read() != i) do ;
      stdout.write(line_buff[0..#off]);
      outGo[nextTask].write(i+chunkSize);
    }
    }
  }
}

//
// Deterministic random number generator
//
var lastRand = seed;

proc getRands(n, arr) {
  //  writef("tid %i got turn\n", tid);
  for i in 0..#n {
    lastRand = (lastRand * IA + IC) % IM;
    arr[i] = lastRand;
  }
}
