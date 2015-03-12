/* 
Example usage of the FFTW module in Chapel. This particular file demonstrates the single-threaded version of
the code.

To compile this code :
   chpl testFFTW.chpl
If FFTW is not on your include/library paths, you can do 
   chpl testFFTW.chpl -I$FFTW_DIR/include -L$FFTW_DIR/lib
where $FFTW_DIR points to your FFTW installation.

Note that you do not need to explicitly include the header or library files; the module uses an experimental
feature of the Chapel compiler to automatically include these.

The FFTW module uses the FFTW3 API, and currently just implements the basic interface.
We will assume that the reader is familiar with using FFTW; more 
details are at http://www.fftw.org. 

The code computes a series of 1,2 and 3D transforms, exercising the complex <-> complex, and real<->complex
transforms (both in and out of place). The output of the code should be a series of small numbers ( <= 10^-13);
see testFFTW.good for example values (it is possible that your values might differ). 

The data for these tests is in arr{1,2,3}d.dat. The format of these files is documented below.
*/
use FFTW;

/* Utility function to print the maximum absolute deviation between values computed by this code, 
   and "truth". The true values are computed using Mathematica v10 */
proc printcmp(x, y) {
  var err = max reduce abs(x-y);
  writeln(err);
}

/* This is main test code, parametrized on the number of dimensions ndim. 
  fn is the file that contains the test data.
*/
proc runtest(param ndim : int, fn : string) {
  var dims : ndim*int(32); 

  /* We define a number of different domains below, corresponding to complex input/output arrays,
     real (input) -> complex (output) out-of-place arrays, and real <-> complex in-place arrays.

     The domains are :
     * D : for complex <-> complex transforms. This domain is also used for the real array in 
           a real->complex out-of-place transform.
     * cD : for the complex array in a real <-> complex out-of-place transform.
     * rD : for the real array in a real <-> complex in-place transform. This includes the padding needed 
            by the in-place transform. D is a sub-domain of this, and can be used to extract the real array, 
            without padding.
     * reD, imD : Utility domains that access the real/complex parts of the complex array in a real<->complex in-place transform.
  */
  var D : domain(ndim);
  var rD,cD,reD,imD : domain(ndim,int,true); 
  

  /* Read in the arrays from the file below. A,B are the arrays that will be used in the FFTW calls, 
     goodA and goodB store the true values. 

     Note that goodA is all real, allowing us to reuse the same array for the real<->complex tests.

     The file format is as follows (all little-endian):
        [ndim] int32 : dimensions of the array
        [narr] real64 : the real components of A (imaginary components are all zero). narr = N_1*N_2*..*N_ndim (product of dimensions)
        [narr] complex128 : the components of B (stored as real-imaginary pairs).

        The arrays are all stored in C (row-major) order.
  */
  var A,B,goodA,goodB : [D] complex;
  {
    var f = open(fn,iomode.r).reader(kind=iokind.little);
    // Read in dimensions 
    for ii in 1..ndim {
      f.read(dims(ii));
    }
    /* The code below sets the domain D. Note that the if statements are folded at compile
       time. This would be more compact with a select statement, but that isn't folded on compilation.
    */
    if (ndim == 1) {
      D = 0.. #dims(ndim);
    }
    if (ndim == 2) {
      D = {0.. #dims(1),0.. #dims(ndim)};
    }
    if (ndim == 3) {
      D = {0.. #dims(1),0.. #dims(2), 0.. #dims(ndim)};
    }

    // Read in the arrays
    for val in goodA {
      f.read(val.re);
      val.im = 0;
    }
    for val in goodB {
      f.read(val);
    }
    f.close();
    writeln("Data read...");
  }

  /* Now set the remaining domains. As above, the if statements are folded on compilation.

     The reader is referred to the FFTW documentation on the storage order for the in-place 
     transforms (Sec 2.4 and 4.3.4).
  */
  if (ndim==1) {
    var ldim = dims(1)/2 + 1;
    // Domains for real FFT
    rD = 0.. #(2*ldim); // Padding to do in place transforms
    cD = 0.. #ldim;
    // Define domains to extract the real and imaginary parts for inplace transforms
    reD = rD[0..(2*ldim-1) by 2]; 
    imD = rD[1..(2*ldim-1) by 2]; 
  }
  if (ndim==2) {
    // Domains for real FFT
    var ldim = dims(2)/2+1;
    rD = {0.. #dims(1),0.. #(2*ldim)}; // Padding to do in place transforms
    cD = {0.. #dims(1),0.. #ldim};
    // Define domains to extract the real and imaginary parts for in place transforms
    reD = rD[..,0..(2*ldim-1) by 2]; 
    imD = rD[..,1..(2*ldim-1) by 2]; 
  }
  if (ndim==3) {
    // Domains for real FFT
    var ldim = dims(3)/2+1;
    rD = {0.. #dims(1),0.. #dims(2),0.. #(2*ldim)}; // Padding to do in place transforms
    cD = {0.. #dims(1),0.. #dims(2),0.. #ldim};
    // Define domains to extract the real and imaginary parts for in place transforms
    reD = rD[..,..,0..(2*ldim-1) by 2]; 
    imD = rD[..,..,1..(2*ldim-1) by 2]; 
  }

  // FFTW does not normalize inverse transform, so just compute the normalization constant.
  var norm = * reduce dims;

  /* We start the FFT tests below. The structure is the same :
      * Define plans for forward and reverse transforms.
      * Execute forward transform A -> B. 
      * Compare with goodB.
      * Execute reverse transform B -> A and normalize.
      * Compare with goodA.
      * Cleanup plans
  */

  /* Complex <-> complex 
  */
	var fwd = plan_dft(A, B, FFTW_FORWARD, FFTW_ESTIMATE);
	var rev = plan_dft(B, A, FFTW_BACKWARD, FFTW_ESTIMATE);
	// Test forward and reverse transform
	A = goodA;
	execute(fwd);
	printcmp(B,goodB);
	execute(rev);
	A /= norm; 
	printcmp(A,goodA);
	destroy_plan(fwd);
	destroy_plan(rev);

	// Test in-place transforms
	fwd = plan_dft(A, A, FFTW_FORWARD, FFTW_ESTIMATE);
	rev = plan_dft(A, A, FFTW_BACKWARD, FFTW_ESTIMATE);
	A = goodA;
	// Test forward and reverse transform
	A = goodA;
	execute(fwd);
	printcmp(A,goodB);
	execute(rev);
	A /= norm; // FFTW does an unnormalized transform
	printcmp(A,goodA);
	destroy_plan(fwd);
	destroy_plan(rev);

  // Testing r2c and c2r
  var rA : [D] real(64); // No padding for an out-of place transform
  var cB : [cD] complex;
  fwd = plan_dft_r2c(rA,cB,FFTW_ESTIMATE);
  rev = plan_dft_c2r(cB,rA,FFTW_ESTIMATE);
  rA[D] = goodA.re;
  execute(fwd);
  printcmp(cB,goodB[cD]);
  execute(rev);
  rA /= norm;
  printcmp(rA[D],goodA.re);
  destroy_plan(fwd);
  destroy_plan(rev);
  // In place transform
  var rA2 : [rD] real(64);
  fwd = plan_dft_r2c(D,rA2,FFTW_ESTIMATE);
  rev = plan_dft_c2r(D,rA2,FFTW_ESTIMATE);
  rA2[D] = goodA.re;
  execute(fwd);
  printcmp(rA2[reD],goodB[cD].re);
  printcmp(rA2[imD],goodB[cD].im);
  execute(rev);
  rA2 /= norm;
  printcmp(rA2[D],goodA.re);
  destroy_plan(fwd);
  destroy_plan(rev);

}


proc testAllDims() {
  writeln("1D");
  runtest(1, "arr1d.dat");
  writeln("2D");
  runtest(2, "arr2d.dat");
  writeln("3D");
  runtest(3, "arr3d.dat");
}

proc main() {
  testAllDims();
  cleanup();
}
