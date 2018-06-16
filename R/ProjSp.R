#'  \code{ProjSp} produces samples from the Projected Normal spatial model  posterior distribution
#' as proposed in
 #' @param  x a vector of n circular data in [0,2\pi)]
#' @param  coords an nx2 matrix with the sites coordinates
#' @param  start a list of 4 elements giving initial values for the model parameters. Each elements is a vector with \code{n_chains} elements
#' \itemize{
#' \item 	alpha the mean,
#' \item  rho the spatial decay parameter,
#' \item sigma2 the process variance,
#' \item k the vector of \code{length(x)}  winding numbers
#' }
#' @param  prior a list of 4 elements to define priors  for the model parameters:
#' \describe{
#' \item{alpha} a vector of 2 elements the mean and the variance of  a Gaussian distribution, default is  mean \eqn{\pi} and variance 1,
#' \item{rho}  a vector of 2 elements defining the shape and rate of a gamma distribution,
#' \item{ sigma2}  a vector of 2 elements defining the shape and rate of an inverse-gamma distribution
#' \item{beta} a vector of 3 elements (c,a,b). For the nugget (if present) we use the parametrization \eqn{\beta=nugget/\sigma^2} and then a scaled Beta distribution is chosen as prior i.e. c*Beta(a,b), with a,b,c>0.
#' }
#' @param sd.prop= list of 3 elements. To run the MCMC for the rho and sigma2 parameters we use an adaptive metropolis and in sd.prop we build a list of initial guesses for these two parameters and the beta parameter
#' @param nugget  logical, if the measurement error term must be added, default to TRUE
#' @paramiter  iter number of iterations
#' @param bigSim a vector of 2 elements with  the burnin and the chain thinning
#' @param accept.ratio it is the desired acceptance ratio in the adaptive metropolis
#' @param adapt.param a vector of 3 elements giving the iteration number at which the adaptation must start  and end. The third element (esponente)  must be a number in (0,1) is a parameter ruling the speed of changes in the adaptation algorithm, it is recommended to set it close to 1, if it is too small  non positive definite matrices may be generated and the program crashes.
#' @param corr_fun  characters, the name of the correlation function, currently implemented functions are c("exponential", "matern")
#' @param kappa_matern numeric, the smoothness parameter of the Matern correlation function, k=0.5 is the exponential function
#' @param n_chain numeric the number of chains to be lunched (we recommend to use at least 2 for model diagnostic)
#' @param parallel logical, if the multiplechains  must be lunched in parallel
#' @param n_cores numeric, the number of cores to be used in the implementatiopn,it must be equal to the number of chains
#'@return it returns a list of \code{n_chains} lists each with elements
#' \code{alpha}, \code{rho}, \code{beta}, \code{sigma2} vectors with the thinned chains, \code{k} a matrix with \code{nrow=length(x)} and \cod{ncol=} the length of thinned chains and \code{corr_fun} characters with the type of spatial correlation chosen
#' @examples
#' data(april)
#' attach(april)
#' ### an example on a storm
#' ## select an hour on the entire Adriatic
#' storm1<-apr6.2010[apr6.2010$hour=="20:00",]
#' plot(storm1$Lon,storm1$Lat, col=storm1$state,pch=20)
#' legend("bottomleft",c("calm","transition","storm"),pch=20,col=c(1,2,3),title="Sea state")
#' #we select only the storm area
# storm2<-apr6.2010[apr6.2010$hour=="20:00" & apr6.2010$state=="storm",]
#' ### we have to convert the directions into radians
#' storm2$Dmr<-storm2$Dm*pi/180
#' ##The storms comes from south-east
#' ### We hold 10% of the locations for validation
#' nval<-round(nrow(storm2)*0.1)
#' sample.val<-sort(sample(c(1:nrow(storm2)),nval))
#' train<-storm2[-sample.val,]
#' test<-storm2[sample.val,]
#' #It is better  to convert the coordinates into UTM as the algorithm uses euclidean distance
#' coords<-storm2[,3:4]
#' colnames(coords)=c("X","Y")
#' attr(coords,"projection")<-"LL"
#' attr(coords,"zone")<-32
#' coords2<-PBSmapping::convUL(coords,km=T)
#' coords.train<-coords2[-sample.val,]
#' coords.test<-coords2[sample.val,]
#' distance_matrix<-dist(coords2)
#' ### Now we build the information for the priors
#' rho_max <- 3./min(distance_matrix[which(distance_matrix > 0)])
#' rho_min <- 3./max(distance_matrix[which(distance_matrix > 0)])
#' Now run the posterior estimation see \\code{\link{WrapSp}} for details
#' start1=list("alpha"      = c(2*pi,3.14),
#'	 "rho"     = c(.5*(rho_min + rho_max),.1*(rho_min + rho_max)),
#'	 "sigma2"    = c(1,0.1),
#'	 "beta"     = c(.3,0.01),
#'	 "k"       = rep(0, nrow(train)))
#'    # Running WrapSp may take some time
#' mod = WrapSp(
#' x     = train$Dmr,
#' coords    = coords.train,
#' start   = start1 ,
#' prior   = list("alpha"      = c(pi,10), # N
#' "rho"     = c(rho_min, rho_max), #c(1.3,100), # G
#' "sigma2"    = c(3,0.5),
#' "beta"      = c(1,1,2)  # nugget prior
#' ) ,
#' nugget = TRUE,
#' sd_prop   = list( "sigma2" = 1, "rho" = 0.3, "beta" = 1),
#' iter    = 30000,
#'  bigSim    = c(burnin = 15000, thin = 10),
#' accept_ratio = 0.5,
#' adapt_param = c(start = 1000, end = 10000, esponente = 0.95),
#' corr_fun = "exponential",
#' n_chains=2,
#' parallel=T,
#' n_cores=2)
#' ## we check convergence
#' check<- ConvCheck(mod)
#' check$Rhat ### convergence has been reached
#' par(mfrow=c(2,2))
#' coda::traceplot(check$mcmc)
#' #or/and
#' require(coda)
#' plot(check$mcmc) # remember that alpha is a circular variable
#' #### a more complex situation, when calm and transition states are mixed
#' data(may6.2010.00)

ProjSp  <- function(
  theta     = theta,
  coords    = coords,
  start   = list("alpha"      = c(1,1,.5,.5),
                 "rho0"     = c(0.1, .5),
                 "rho"      = c(.1,.5),
                 "sigma2"    = c(0.1, .5),
                 "r"       = sample(1,length(theta), replace = T)),
  prior   = list("rho0"      = c(8,14),
                 "rho"     = c(8,14),
                 "sigma2"    = c(),
                 "alpha_mu" = c(1., 1.),
                 "alpha_sigma" = c()
  ) ,
  sd_prop   = list( "sigma2" = 0.5, "rho0" = 0.5, "rho" = 0.5,"beta" = .5, "sdr" = sample(.05,length(theta), replace = T)),
  iter    = 1000,
  bigSim    = c(burnin = 20, thin = 10),
  accept_ratio = 0.234,
  adapt_param = c(start = 1, end = 10000000, esponente = 0.9, sdr_update_iter = 50),
  corr_fun = "exponential", kappa_matern = .5,
  n_chains = 2, parallel = FALSE, n_cores = 2)
{

  ## ## ## ## ## ## ##
  ## Sim
  ## ## ## ## ## ## ##
  ## ## ## ## ## ## ##

  #######
  burnin					=	bigSim[1]
  thin					= 	bigSim[2]
  n_j						=	length(theta)
  H						=	as.matrix(stats::dist(coords))

  ######
  ad_start				=	adapt_param["start"]
  ad_end					=	adapt_param["end"]
  ad_esp					=	adapt_param["esponente"]
  sdr_update_iter = adapt_param["sdr_update_iter"]

  #####

  iter_1          		= burnin
  iter_2					=	round((iter - burnin)/thin)

  # priori
  prior_rho0				=	prior[["rho0"]]
  prior_rho				=	prior[["rho"]]
  prior_sigma2			=	prior[["sigma2"]]
  prior_alpha_sigma = prior[["alpha_sigma"]]
  prior_alpha_mu = prior[["alpha_mu"]]
  # sd proposal
  sdprop_sigma2 = sd_prop[["sigma2"]]
  sdprop_rho0	= sd_prop[["rho0"]]
  sdprop_rho	= sd_prop[["rho"]]
  sdprop_r	= sd_prop[["sdr"]]
  # starting
  start_alpha				=	start[["alpha"]]
  if (length(start_alpha) != 2*n_chains) {stop(paste('start[["alpha"]] length should be equal to 2*n_chains (',
                                                  n_chains,')', sep = ''))}
  start_rho				=	start[["rho"]]
  if (length(start_rho) != n_chains) {stop(paste('start[["rho"]] length should be equal to n_chains (',
                                                n_chains,')', sep = ''))}
  start_rho0				=	start[["rho0"]]
  if (length(start_rho) != n_chains) {stop(paste('start[["rho"]] length should be equal to n_chains (',
                                                 n_chains,')', sep = ''))}
  start_sigma2			=	start[["sigma2"]]
  if (length(start_sigma2) != n_chains) {stop(paste('start[["sigma2"]] length should be equal to n_chains (',
                                                   n_chains,')', sep = ''))}
  start_r					=	start[["r"]]

  acceptratio = accept_ratio
  corr_fun = corr_fun
  corr_fun_list <- c("exponential", "matern") #,"gaussian"
  if (!corr_fun %in% corr_fun_list) {
    error_msg <- paste("You should use one of these correlation functions: ",paste(corr_fun_list,collapse = "\n"),sep = "\n")
    stop(error_msg)
  } else{
    if (corr_fun == "matern" & kappa_matern <= 0) stop("kappa_matern should be strictly positive")}

    if (parallel) {
      ccc <- try(library(doParallel))
      if (class(ccc) == 'try-error') stop("You shoul install doParallel package in order to use parallel = TRUE option")
      cl <- makeCluster(n_cores)
      registerDoParallel(cl)
      out <- foreach(i = 1:n_chains) %dopar% {
        out_temp <- ProjSpRcpp(ad_start, ad_end, ad_esp,
                                     burnin, thin,iter_1,iter_2,
                                     n_j, sdr_update_iter,
                                     prior_rho0 ,prior_sigma2,prior_rho, prior_alpha_sigma, prior_alpha_mu,
                                     sdprop_rho0,sdprop_sigma2,sdprop_rho, sdprop_r,
                                     start_rho0[i],start_sigma2[i], start_rho[i], start_alpha[(2*i-1):(2*i)], start_r,
                                     theta,H, acceptratio,
                                     corr_fun, kappa_matern)
        out_temp
      }
      stopCluster(cl)
    } else {
      out <- list()
      for (i in 1:n_chains) {
        out_temp <- ProjSpRcpp(ad_start, ad_end, ad_esp,
                            burnin, thin,iter_1,iter_2,
                            n_j, sdr_update_iter,
                            prior_rho0 ,prior_sigma2,prior_rho, prior_alpha_sigma, prior_alpha_mu,
                            sdprop_rho0,sdprop_sigma2,sdprop_rho, sdprop_r,
                            start_rho0[i],start_sigma2[i], start_rho[i], start_alpha[(2*i-1):(2*i)], start_r,
                            theta,H, acceptratio,
                            corr_fun, kappa_matern)

        out[[i]] <- out_temp
      }
    }

  return(out)
}