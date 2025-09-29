//+------------------------------------------------------------------+
//|                                                   Numpy test.mq5 |
//|                                    Copyright 2024, Omega Joctan. |
//|                 https://www.mql5.com/en/users/omegajoctan/seller |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Omega Joctan."
#property link      "https://www.mql5.com/en/users/omegajoctan/seller"
#property version   "1.00"

#include <Numpy.mqh>
CNumpy np;
//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
//--- Initialization
/*  
    // Vectors One-dimensional
    
    Print("numpy.full: ",np.full(10, 2));
    Print("numpy.ones: ",np.ones(10));
    Print("numpy.zeros: ",np.zeros(10));
    
    // Matrices Two-Dimensional
    
    Print("numpy.full:\n",np.full(3,3, 2));
    Print("numpy.ones:\n",np.ones(3,3));
    Print("numpy.zeros:\n",np.zeros(3,3));
    Print("numpy.eye:\n",np.eye(3,3));
    Print("numpy.identity:\n",np.identity(3));
    
//--- Mathematical functions
   
    Print("numpy.e: ",np.e);
    Print("numpy.euler_gamma: ",np.euler_gamma);
    Print("numpy.inf: ",np.inf);
    Print("numpy.nan: ",np.nan);
    Print("numpy.pi: ",np.pi);

    vector a = {1,2,3,4,5};
    vector b = {1,2,3,4,5};  
    
    Print("np.add: ",np.add(a, b));
    Print("np.subtract: ",np.subtract(a, b));
    Print("np.multiply: ",np.multiply(a, b));
    Print("np.divide: ",np.divide(a, b));  
    Print("np.power: ",np.power(a, 2));
    Print("np.sqrt: ",np.sqrt(a));
    Print("np.log: ",np.log(a));
    Print("np.log1p: ",np.log1p(a)); 

//--- Statistical functions
   
     vector z = {1,2,3,4,5};
    
     Print("np.sum: ", np.sum(z));
     Print("np.mean: ", np.mean(z));
     Print("np.var: ", np.var(z));
     Print("np.std: ", np.std(z));
     Print("np.median: ", np.median(z));
     Print("np.percentile: ", np.percentile(z, 75));
     Print("np.quantile: ", np.quantile(z, 75));
     Print("np.argmax: ", np.argmax(z));
     Print("np.argmin: ", np.argmin(z));
     Print("np.max: ", np.max(z));
     Print("np.min: ", np.min(z));
     Print("np.cumsum: ", np.cumsum(z));
     Print("np.cumprod: ", np.cumprod(z));
     Print("np.prod: ", np.prod(z));
     
     vector weights = {0.2,0.1,0.5,0.2,0.01};
     Print("np.average: ", np.average(z, weights));
     Print("np.ptp: ", np.ptp(z));

//--- Random numbers generating
    
    //np.random.seed(42);
    
    Print("---------------------------------------:");  
    Print("np.random.uniform: ",np.random.uniform(1,10,10));
    Print("np.random.normal: ",np.random.normal(10,0,1));
    Print("np.random.exponential: ",np.random.exponential(10));
    Print("np.random.binomial: ",np.random.binomial(10, 5, 0.5));
    Print("np.random.poisson: ",np.random.poisson(4, 10));
    
    vector data = {1,2,3,4,5,6,7,8,9,10};
    //np.random.shuffle(data);
    //Print("Shuffled: ",data);
    
    Print("np.random.choice replace=True: ",np.random.choice(data, (uint)data.Size(), true));
    Print("np.random.choice replace=False: ",np.random.choice(data, (uint)data.Size(), false));
   
   
    Print("np.fft.fftfreq: ",np.fft.fft_freq(10, 1));
    
    vector signal = {0. , 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9};
    
    vectorc fft_res = np.fft.fft(signal); //perform fft
    Print("np.fft.fft: ",fft_res); //fft results
    Print("np.fft.ifft: ",np.fft.ifft(fft_res)); //Original signal
    
    Print("np.fft.rfft: ",np.fft.rfft(signal));
    
    //--- Linear algebra
    
    
    matrix m = {{1,1,10},
                {1,0.5,1},
                {1.5,1,0.78}};
                
    Print("np.linalg.inv:\n",np.linalg.inv(m));
    Print("np.linalg.det: ",np.linalg.det(m));
    Print("np.linalg.det: ",np.linalg.kron(m, m));
    Print("np.linalg.eigenvalues:",np.linalg.eig(m).eigenvalues," eigenvectors: ",np.linalg.eig(m).eigenvectors);
    Print("np.linalg.norm: ",np.linalg.norm(m, MATRIX_NORM_P2));
    Print("np.linalg.svd u:\n",np.linalg.svd(m).U, "\nv:\n",np.linalg.svd(m).V);
        
    
    matrix a = {{1,1,10},
                {1,0.5,1},
                {1.5,1,0.78}};
                
    vector b = {1,2,3};
    
    Print("np.linalg.solve ",np.linalg.solve(a, b));
    Print("np.linalg.lstsq: ", np.linalg.lstsq(a, b));
    Print("np.linalg.matrix_rank: ", np.linalg.matrix_rank(a));
    Print("cholesky: ", np.linalg.cholesky(a));
    Print("matrix_power:\n", np.linalg.matrix_power(a, 2));

    //--- Polynomial
    
    vector X = {0. , 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9};
    vector y = MathPow(X, 3) + 0.2 * np.random.randn(10);  // Cubic function with noise
    
    CPolynomial poly;
    
    Print("coef: ", poly.fit(X, y, 3));
           
//--- Polynomial utils

    vector p = {1,-3, 2};
    vector q = {2,-4, 1};
    
    Print("polyadd: ",np.polyadd(p, q));
    Print("polysub: ",np.polysub(p, q));
    Print("polymul: ",np.polymul(p, q));
    Print("polyder:", np.polyder(p));
    Print("polyint:", np.polyint(p)); // Integral of polynomial
    Print("plyval x=2: ", np.polyval(p, 2)); // Evaluate polynomial at x = 2
    Print("polydiv:", np.polydiv(p, q).quotient," ",np.polydiv(p, q).remainder);

*/       
    //--- Common methods
    
    vector v = {1,2,3,4,5,6,7,8,9,10};  
    
    Print("------------------------------------");  
    Print("np.arange: ",np.arange(10));
    Print("np.arange: ",np.arange(1, 10, 2));
    
    matrix m = {
      {1,2,3,4,5},
      {6,7,8,9,10}
    };
      
    Print("np.flatten: ",np.flatten(m));
    Print("np.ravel: ",np.ravel(m));
    Print("np.reshape: ",np.reshape(v, 5, 2));
    Print("np.reshape: ",np.reshape(m, 2, 3));
   
    Print("np.expnad_dims: ",np.expand_dims(v, 1));
    Print("np.clip: ", np.clip(v, 3, 8));
   
    //--- Sorting
   
    Print("np.argsort: ",np.argsort(v));
    Print("np.sort: ",np.sort(v));
   
    //--- Others
    
    matrix z = {
      {1,2,3},
      {4,5,6},
      {7,8,9},
    };
      
    Print("np.concatenate: ",np.concat(v,  v));
    Print("np.concatenate:\n",np.concat(z,  z, AXIS_HORZ));
    
    vector y = {1,1,1};
    
    Print("np.concatenate:\n",np.concat(z,  y, AXIS_VERT));
    Print("np.dot: ",np.dot(v, v));
    Print("np.dot:\n",np.dot(z, z));
    Print("np.linspace: ",np.linspace(1, 10, 10, true));
    
    Print("np.unique: ",np.unique(v).unique, " count: ",np.unique(v).count);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

