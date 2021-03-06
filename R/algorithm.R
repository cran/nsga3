#' NSGA III for Multi-Objective Feature Selection
#'
#'@description
#'An adaptation of Non-dominated Sorting Genetic Algorithm III for multi
#'objective feature selection tasks.
#'Non-dominated Sorting Genetic Algorithm III is a genetic algorithm that solves multiple
#'optimization problems simultaneously by applying a non-dominated sorting
#'technique. It uses a reference points based selection operator to explore
#'solution space and preserve diversity. See the paper by K. Deb and
#'H. Jain (2014) <DOI:10.1109/TEVC.2013.2281534> for a detailed description of the algorithm.
#'
#'
#'
#'@param df An original dataset.
#'@param target Name of a column (a string), which contains classification target variable.
#'@param obj_list A List of objective functions to be optimizied.
#'Must be a list of objects of type closure.
#'@param obj_names A Vector of the names of objective functions.
#'Must match the atguments passed to pareto.
#'@param pareto A Pareto criteria for non-dominated sorting. Should be passed in a form:
#'\eqn{low(objective_1)*high(objective_2)}
#'See description of \code{\link[rPref]{low}} for more details.
#'@param pop_size Size of the population.
#'@param max_gen Number of generations.
#'@param model A \code{\link[mlr]{makeLearner}} object. A model to be used for
#'classification task.
#'@param resampling A \code{\link[mlr]{makeResampleDesc}} object.
#'@param num_features TRUE if algorithm should minimize number of features as one of objectives.
#'You must pass a respective object to pareto as well as obj_names.
#'@param mutation_rate Probability of switching the value of a certain gene to its opposite.
#'Default value 0.1.
#'@param threshold Threshold applied during majority vote when calculating final output.
#'Default  value 0.5.
#'@param feature_cost A vector of feacure costs. Must be equal ncol(df)-1.
#'You must pass a respective object to pareto as well as obj_names.
#'@param r_measures A list of performance metrics for \code{\link[mlr]{makeResampleDesc}} task.
#'Default "mmce"
#'@param cpus Number of sockets to be used for parallelisation. Default value is 1.
#'@return A list with the final Pareto Front:
#'\describe{
#' \item{Raw}{A list containing two items:
#' \enumerate{
#' \item A list with final Pareto Front individuals
#' \item A data.frame containing respective fitness values
#' }
#' }
#' \item{Per individual}{Same content, structured per individual}
#' \item{Majority vote}{Pareto Front majority vote for dataset features}
#' \item{Stat}{Runtime, dataset details, model}
#' }
#'@references K. Deb, H. Jain (2014) <DOI:10.1109/TEVC.2013.2281534>
#'
#'@note
#' Be cautious with setting the size of population and maximum generations.
#' Since NSGA III is a wrapper feature selection method, a model has to be retrained
#' N*number of generation +1 times, which may involve high computational costs.
#' A 100 x 100 setting should be enough.
#'
#' This adaptation of NSGA III algorithm for Multi Objective Feature Selection is currently
#' available only for classification tasks.
#'
#' #'As any other Genetic Algorithm (GA), NSGA III includes following steps:
#'\enumerate{
#' \item An initial population Pt of a size N is created
#' \item A model is trained on each individual (subset) and fitness values are assigned
#' \item An offsping population of a size N is created by crossover and mutation operators
#' \item The offspring population is combined with its parent population
#' \item A combined population of a size 2N is split into Pareto Fronts using non-dominated
#' sorting technique
#' \item A next generation's population Pt+1 of size N is selected from the top Pareto Fronts
#' with help of elitism based selection operator
#' }
#' The loop is repeated until the final generation is reached
#'
#' Each generation is populated by individuals representing different subsets.
#' Each individual is represented as a binary vector, where each gene represents
#' a feature in the original dataset.
#'
#' @examples
#' xgb_learner <- mlr::makeLearner("classif.xgboost", predict.type = "prob",
#'                             par.vals = list(
#'                             objective = "binary:logistic",
#'                             eval_metric = "error",nrounds = 2))
#'
#' rsmp <- mlr::makeResampleDesc("CV", iters = 2)
#' measures <- list(mlr::mmce)
#'
#' f_auc <- function(pred){auc <- mlr::performance(pred, auc)
#'                         return(as.numeric(auc))}
#' objective <- c(f_auc)
#' o_names <- c("AUC", "nf")
#' par <- rPref::high(AUC)*rPref::low(nf)
#'
#' nsga3fs(df = german_credit, target = "BAD", obj_list = objective,
#'         obj_names = o_names, pareto = par, pop_size = 1, max_gen = 1,
#'         model = xgb_learner, resampling = rsmp,
#'         num_features = TRUE, r_measures = measures, cpus = 2)
#'
#'
#'
#'
#'
#'@export nsga3fs




#######################################################################################

##################            ALGORITHM            ####################################

#######################################################################################




nsga3fs <- function(df, target, obj_list, obj_names,
                    pareto, pop_size, max_gen,
                    model,
                    resampling = FALSE,
                    num_features = TRUE,
                    mutation_rate=0.1,
                    threshold = 0.5,
                    feature_cost = FALSE,
                    r_measures = list(mlr::mmce),
                    cpus=1){


  #INITIAL POPULATION------------------------------------------------------------------



  generate_init_pop <- function(data, size){

    generate_ind <- function(len, p){
      ind <- sample(0:1, size = len, replace = TRUE, prob = c(p,1-p))
      return(ind)
    }

    len <- ncol(data)-1
    population <- list()
    probs <- seq(0.1,0.9,length.out = size)

    for(i in 1:size){
      population[[i]] <- generate_ind(len,probs[i])
    }
    return(population)
  }

  #NON-DOMINATED SORTING

  non_dom_sort <- function(pop, pareto_criteria){
    #works with data frames only
    sorted_pop <- psel(pop, pareto_criteria, top = nrow(pop), show_level = TRUE)
    return(sorted_pop)
  }



  #######################################################################################

  ##################     CROSSOVER AND MUTATION   #######################################

  #######################################################################################



  #CROSSOVER


  create_children <- function(mating_pool){

    crossover <- function(ind1, ind2){
      child <- vector(length=length(ind1))
      for(i in 1:length(child)){
        if(runif(1,0,1)>0.5){
          child[i] <- ind1[i]
        } else {
          child[i] <- ind2[i]
        }
      }
      return(child)
    }


    children <- list()
    len <- length(mating_pool)
    #for(i in 1:(round(len/2,0))){
    for(i in 1:len){
      children[[i]] <- crossover(mating_pool[[i]],mating_pool[[(len-i+1)]])
    }
    return(children)
  }


  #MUTATION---------------------------------------------------------------------------



  mutate_pop <- function(pop, mutation_rate=mutation_rate){

    mutate_ind <- function(ind, mutation_rate){
      for(i in 1:length(ind)){
        if(runif(1,0,1) < mutation_rate){
          ind[i] <- as.integer(!ind[i])
        }
      }
      if(sum(ind) == 0){
        i <- sample(length(ind))
        ind[i] <- 1
      }
      return(ind)
    }

    mutated_pop <- mpop <- lapply(pop,mutate_ind,mutation_rate)
    return(mutated_pop)
  }




  #######################################################################################

  ##################      EVALUATION STEP       #########################################

  #######################################################################################


  ####### Levels:
  ####### evaluate_population           - 1st
  #######   evaluate_ind                - 2nd
  #######       select_columns          - 3rd
  #######       perform_prediction      - 3rd

  evaluate_population <- function(pop,
                                  df,
                                  target,
                                  objectives,
                                  model,
                                  resampling,
                                  num_features,
                                  feature_cost,
                                  r_measures){


    #-2nd------------------------------------------------------------------------------------

    evaluate_ind <- function(ind,
                             df,
                             target,
                             objectives,
                             model,
                             resampling,
                             num_features,
                             feature_cost,
                             r_measures){


      select_columns <- function(df, target, ind){

        goods <- data.frame(df[,c(target)])
        colnames(goods) <- target

        cnames <- colnames(df)
        cnames <- cnames[-which(cnames==target)]

        selected_columns <- cnames[as.logical(ind)]

        df <- df[,selected_columns]
        df <- cbind(df,goods)
        df <- mlr::createDummyFeatures(df, target = target, method = 'reference')

        return(df)
      }

      #-3rd------------------------------------------------------------------------------------


      perform_prediction <- function(df, target, model,
                                     resampling, r_measures){

        learner <- model
        trainTask <- mlr::makeClassifTask(data = df, target = target, positive=1)
        rdesc <- resampling
        pred <- mlr::resample(learner, trainTask, rdesc, show.info = FALSE,
                              measures = r_measures)

        res <- pred$pred
        return(res)
      }
      #-3rd------------------------------------------------------------------------------------
      #evaluate_ind cont.

      dat <- select_columns(df, target, ind)
      res <- perform_prediction(dat, target, model, resampling, r_measures)


      get_objective_values <- function(a) {
        # call each function to a
        lapply(objectives, function(f) f(a))
      }

      ans <- get_objective_values(res)

      obj_vals <- data.frame()

      for(i in 1:length(ans)){
        obj_vals[1,i] <- ans[[i]]
      }

      if(num_features == TRUE){
        n <- length(obj_vals)+1
        obj_vals[1,n]<- sum(ind)
      }

      #if(feature_cost != FALSE){
      if(any(feature_cost)){
        cost <- sum(feature_cost[as.logical(ind)])
        n <- length(obj_vals)+1
        obj_vals[1,n]<- cost
      }
      # }

      return(obj_vals)
    }
    #-1st------------------------------------------------------------------------------------
    #evaluate_pop cont.

    evaluated_pop_list <- parallelLapply(pop,
                                         evaluate_ind,
                                         df,
                                         target,
                                         objectives,
                                         model,
                                         resampling,
                                         num_features,
                                         feature_cost,
                                         r_measures)

    evaluated_pop_res <- data.frame()

    evaluated_pop_res <- do.call(rbind, evaluated_pop_list)

    return(evaluated_pop_res)
  }



  #######################################################################################

  ##################   REFERENCE POINTS         #########################################

  #######################################################################################




  ref_points <- function(n_objectives){
    m <- n_objectives
    p <- m+1

    if( m==2){
      a <- seq(0,0.5,0.05)
      b <- seq(0.5,0,-0.05)
      refs <- cbind(a,b)
      return(refs)
    }

    #N = number of points
    a <- m+p-1
    n <- factorial(a)/(factorial(p)*factorial(a-p))

    #divisions per side
    d <- n/m-1
    step <- 1/d

    options <- c(0,1)
    for(j in 1:d){
      options[(2+j)]<- step*j
    }

    point <- vector(length=m)
    point[1]<-1
    for(i in 2:m){
      point[i]<-0
    }
    set <- rbind(point)

    while(nrow(unique(set))<n){
      point <- vector(length=m)
      for(col in 1:m){
        point[col] <- sample(options,1)
      }
      if(sum(point)==1){
        set <- rbind(set,point)
      }
    }
    set <- unique(set)
    return(set)
  }



  #######################################################################################

  ##################      NORMALISATION         #########################################

  #######################################################################################



  compute_ideal_point <- function(pareto_front){
    z_hat <- vector(length=ncol(pareto_front))
    for(i in 1:length(z_hat)){
      z_hat[i] <- min(pareto_front[,(i)])
    }
    return(z_hat)
  }

  translate_objectives <- function(pareto_front, ideal_point){
    for(i in 1:length(ideal_point)){
      for(j in 1:length(pareto_front[,i])){
        pareto_front[j,i] <- pareto_front[j,i] - ideal_point[i]
      }
    }
    return(pareto_front)
  }

  #different from paper. Just delivers the extrem points
  #description of the achievement scalarizing function (ASF) in paper is not clear

  get_extreme_points <- function(t_pareto_front){
    df <- t_pareto_front
    extreme_points <- vector("list",length=(length(t_pareto_front)))
    for(i in 1:length(extreme_points)){
      extreme_points[[i]] <- df[which.max(df[,i]),]
    }
    return(extreme_points)
  }

  #part-time sol, to be replaced

  get_intercepts <- function(extreme_points){
    intercept <- vector(length=length(extreme_points))
    for(i in 1:length(intercept)){
      intercept[i] <- extreme_points[[i]][[i]]
    }
    return(intercept)
  }


  #a is already calculated from the f_prime, so no need to substract z_min
  normalize <- function(f,a,z_min){
    if(a==0){
      f_n <- f/0.000001
    } else {
      f_n <- f/a
      return(f_n)
    }
  }

  normalize_objectives <- function(front, intercept, ideal_point){
    for(i in 1:ncol(front)){
      for(row in 1:nrow(front)){
        front[row,i] <- normalize(front[row,i], intercept[i], ideal_point[i])
      }
    }
    return(front)
  }




  #######################################################################################

  ##################            NICHING         #########################################

  #######################################################################################



  find_ref_point <- function(point, rp){
    res <- matrix(ncol=ncol(point)+1, nrow=nrow(rp))

    for(i in 1:nrow(rp)){
      d <- dist(rbind(point,rp[i,]))
      res[i,1:(ncol(res)-1)] <- rp[i,]
      res[i,ncol(res)] <- d
    }
    ref <- rp[which.min(res[,ncol(res)]),]
    ans <- which.min(res[,ncol(res)])

    return(ans)
  }

  gen_refs <- function(data, rp){
    ref <- data.frame()
    for(point in 1:nrow(data)){
      p_ref <- find_ref_point(data[point,], rp)
      ref <- rbind(ref,c(p_ref,point))
    }
    colnames(ref) <- c("rp", "data")
    return(ref)
  }

  sel_points <- function(ref_list, dat, k){
    ref_list <- data.frame(ref_list)
    u <- unique(ref_list[,1])
    r <- data.frame()

    for(i in u){
      c <- length(ref_list[ref_list$rp==i,1])
      x <- c(i,c)
      r <- rbind(r,x)
    }
    colnames(r) <- c("rp", "count")
    r <- r[order(r$count),]

    points <- c()
    while(length(points)< k){
      for(i in 1:nrow(r)){
        val <- r[i,1]
        point <- ref_list[ref_list$rp==val,][,2]
        if(length(point)>1){
          point <- sample(point,1)
        }
        if(point %in% points){next}
        else{
          points[length(points)+1] <- point
        }
      }
    }
    res <- dat[points,]
    return(res)
  }

  execute_selection <- function(pf, k){
    m <- ncol(pf)

    ip <- compute_ideal_point(pf) #ip = ideal point
    tpf <- translate_objectives(pf, ip) #tpf = translated pareto front
    ep <- get_extreme_points(tpf) #ep = exteme points
    inter <- get_intercepts(ep) #intercept
    npf <- normalize_objectives(tpf, inter, ip) #normalized pareto front

    rp <- ref_points(m)


    selected_points <- gen_refs(npf, rp)
    selected_points <- sel_points(selected_points, npf,k)

    return(selected_points)
  }



  #######################################################################################

  ###########################         SELECTION      ####################################

  #######################################################################################



  #iterator for selecting points from current generation
  select_next_generation <- function(sorted_evaluated_comb_pop,
                                     combined_pop_individuals, rp, n){
    next_pop = c()

    lvl <- 1
    while(length(next_pop) != n){

      pf <- sorted_evaluated_comb_pop[which(sorted_evaluated_comb_pop$.level==lvl),]
      pf <- pf[,-ncol(pf)]

      len <- length(next_pop)

      if((nrow(pf)+len) <= n){

        for(i in 1:nrow(pf)){
          next_pop[len+i] <- rownames(pf)[i]
        }

        lvl <- lvl+1

      } else {
        k <- n-len
        selected_points <- execute_selection(pf, k)

        for(i in 1:k){
          next_pop[len+i] <- rownames(selected_points)[i]
        }
      }
    }

    next_gen = list()
    eval_next_gen = data.frame()
    for(i in 1:length(next_pop)){
      id <- next_pop[i]
      eval_next_gen <- rbind(eval_next_gen,
                             sorted_evaluated_comb_pop[id,-ncol(sorted_evaluated_comb_pop)])
    }
    ids <- rownames(eval_next_gen)
    ids <- sapply(ids, as.integer)
    next_gen <- combined_pop_individuals[ids]

    ans <- list(next_gen, eval_next_gen)
    return(ans)
  }




  #######################################################################################

  ##################            PREP OUTPUT          ####################################

  #######################################################################################




  maj_vote <- function(pop, df.){

    nfeatures <- length(pop[[1]])
    cols <- lapply(pop,as.logical)
    res <- data.frame()
    for(i in 1:length(cols)){
      for(j in 1:nfeatures){
        res[i,j] <- pop[[i]][j]
      }
    }
    votes <- data.frame()
    names <- colnames(df.)[-length(df.)]
    for(i in 1:nfeatures){
      votes[i,1] <- names[i]
      votes[i,2] <- sum(res[,i])/nrow(res)
    }
    colnames(votes) <- c("feature", "vote")

    return(votes)
  }



  prep_output <- function(pop.,
                          evaluated_pop.,
                          df.,
                          threshold,
                          target,
                          pareto,
                          obj_names.,
                          num_features,
                          ex_time.){

    #-----------------------------------------------------------------------------

    output_per_individual <- function(df., pop, objective_vals){

      feature_names <- colnames(df.)[1:ncol(df.)-1]

      rownames(objective_vals) <- 1:nrow(objective_vals)

      individuals <- list()
      for(i in 1:nrow(objective_vals)){

        values <-  objective_vals[i,]
        features <-  feature_names[as.logical(pop[[i]])]
        element <- list(values, features)

        individuals[i] <- list(element)
      }

      return(individuals)
    }

    #-----------------------------------------------------------------------------

    rownames(evaluated_pop.) <- 1:nrow(evaluated_pop.)
    sorted_fin_pop <- non_dom_sort(evaluated_pop., pareto)
    pf <- sorted_fin_pop[which(sorted_fin_pop$.level==1),]
    pf <- pf[,-ncol(pf)]
    ids <- rownames(pf)
    ids <- sapply(ids, as.integer)

    top_gen = pop.[ids]

    raw <- list(top_gen, pf)
    names(raw) <- c("ind", "objective_values")

    per_ind <- output_per_individual(df. = df., top_gen, pf)


    votes <- maj_vote(top_gen, df.)
    print(votes)
    features <- votes[which(votes$vote >= threshold),]$feature


    majority_vote <- list(votes, features)
    names(majority_vote) <- list("votes", "features")


    result <- list(raw, per_ind, majority_vote, list(ex_time.))

    names(result) <- c("pf_raw", "per_ind", "majority_vote", "runtime")
    return(result)
  }


  #######################################################################################

  ##################         ALGORITHM   BUILDER     ####################################

  #######################################################################################




  parallelStartSocket(cpus, show.info = FALSE)

  start_time <- Sys.time()
  print("Initializing algorithm ...")


  #replace target column at the end
  forder <- colnames(df)
  forder <- forder[-which(forder == target)]
  forder <- c(forder, target)
  df <- df[,forder]

  #m = number of objective functions
  m <- length(obj_names)

  print("- Generating reference points...")
  #generate reference points
  rp <- ref_points(m)

  print("- Generating initial population...")
  #generating initial population
  initial_pop <- generate_init_pop(df, pop_size)


  #Measure approx time per loop

  eval_start <- Sys.time()

  #getting values for objective functions
  evaluated_pop <- evaluate_population(pop = initial_pop, df = df, target = target,
                                       objectives = obj_list,
                                       model = model,
                                       resampling = resampling,
                                       num_features = num_features,
                                       feature_cost = feature_cost,
                                       r_measures = r_measures)
  colnames(evaluated_pop)<-obj_names

  eval_end <- Sys.time()
  print(paste("- Initial evaluation time: ",
              format(as.numeric(difftime(eval_end,eval_start),
                                units="mins"), digits = 3), "min"))

  current_generation <- 0

  pop <- initial_pop

  print("Performing iterations: ")

  all_gens <- list()

  while(current_generation < max_gen){

    iter_start <- Sys.time()

    # assigning new id's to previously selected pouints
    rownames(evaluated_pop) <- 1:nrow(evaluated_pop)

    #crossover
    children <- create_children(sample(pop))

    #mutation
    mutated_children <- mutate_pop(children, mutation_rate)

    #evaluate obj fns for children
    evaluated_children <- evaluate_population(pop = mutated_children, df = df,
                                              target = target,
                                              resampling = resampling,
                                              objectives = obj_list,
                                              model = model,
                                              num_features=num_features,
                                              feature_cost = feature_cost,
                                              r_measures = r_measures)
    colnames(evaluated_children) <- obj_names
    rownames(evaluated_children) <- (length(pop)+1):(length(pop)+length(children))

    #combine parent and child
    combined_pop_individuals <- c(pop, mutated_children) #individuals with actual binary vectors

    evaluated_comb_pop <- rbind(evaluated_pop,evaluated_children) #id's of individuals with obj funs values

    #non-dominated sort
    sorted_evaluated_comb_pop <- non_dom_sort(evaluated_comb_pop, pareto)

    #select individs for next generation
    res <- select_next_generation(sorted_evaluated_comb_pop, combined_pop_individuals, rp, pop_size)
    pop <- res[[1]]
    evaluated_pop <- res[[2]]

    current_generation <- current_generation + 1

    iter_end <- Sys.time()

    print(paste0("- Iteration ", current_generation, "/", max_gen,
                 "   |   Time: ",
                 format(as.numeric(difftime(iter_end,iter_start),
                                   units="mins"), digits = 3), " min"))

  }

  end_time <- Sys.time()

  ex_time <- end_time - start_time

  result <- prep_output(pop. = pop, evaluated_pop. = evaluated_pop,
                        df. = df, threshold = threshold,
                        target = target,
                        obj_names. = obj_names,
                        pareto = pareto,
                        num_features = num_features,
                        ex_time = ex_time)
  parallelStop()

  return(result)
}
