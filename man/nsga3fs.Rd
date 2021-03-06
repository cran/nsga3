% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/algorithm.R
\name{nsga3fs}
\alias{nsga3fs}
\title{NSGA III for Multi-Objective Feature Selection}
\usage{
nsga3fs(df, target, obj_list, obj_names, pareto, pop_size, max_gen, model,
  resampling = FALSE, num_features = TRUE, mutation_rate = 0.1,
  threshold = 0.5, feature_cost = FALSE,
  r_measures = list(mlr::mmce), cpus = 1)
}
\arguments{
\item{df}{An original dataset.}

\item{target}{Name of a column (a string), which contains classification target variable.}

\item{obj_list}{A List of objective functions to be optimizied.
Must be a list of objects of type closure.}

\item{obj_names}{A Vector of the names of objective functions.
Must match the atguments passed to pareto.}

\item{pareto}{A Pareto criteria for non-dominated sorting. Should be passed in a form:
\eqn{low(objective_1)*high(objective_2)}
See description of \code{\link[rPref]{low}} for more details.}

\item{pop_size}{Size of the population.}

\item{max_gen}{Number of generations.}

\item{model}{A \code{\link[mlr]{makeLearner}} object. A model to be used for
classification task.}

\item{resampling}{A \code{\link[mlr]{makeResampleDesc}} object.}

\item{num_features}{TRUE if algorithm should minimize number of features as one of objectives.
You must pass a respective object to pareto as well as obj_names.}

\item{mutation_rate}{Probability of switching the value of a certain gene to its opposite.
Default value 0.1.}

\item{threshold}{Threshold applied during majority vote when calculating final output.
Default  value 0.5.}

\item{feature_cost}{A vector of feacure costs. Must be equal ncol(df)-1.
You must pass a respective object to pareto as well as obj_names.}

\item{r_measures}{A list of performance metrics for \code{\link[mlr]{makeResampleDesc}} task.
Default "mmce"}

\item{cpus}{Number of sockets to be used for parallelisation. Default value is 1.}
}
\value{
A list with the final Pareto Front:
\describe{
\item{Raw}{A list containing two items:
\enumerate{
\item A list with final Pareto Front individuals
\item A data.frame containing respective fitness values
}
}
\item{Per individual}{Same content, structured per individual}
\item{Majority vote}{Pareto Front majority vote for dataset features}
\item{Stat}{Runtime, dataset details, model}
}
}
\description{
An adaptation of Non-dominated Sorting Genetic Algorithm III for multi
objective feature selection tasks.
Non-dominated Sorting Genetic Algorithm III is a genetic algorithm that solves multiple
optimization problems simultaneously by applying a non-dominated sorting
technique. It uses a reference points based selection operator to explore
solution space and preserve diversity. See the paper by K. Deb and
H. Jain (2014) <DOI:10.1109/TEVC.2013.2281534> for a detailed description of the algorithm.
}
\note{
Be cautious with setting the size of population and maximum generations.
Since NSGA III is a wrapper feature selection method, a model has to be retrained
N*number of generation +1 times, which may involve high computational costs.
A 100 x 100 setting should be enough.

This adaptation of NSGA III algorithm for Multi Objective Feature Selection is currently
available only for classification tasks.

#'As any other Genetic Algorithm (GA), NSGA III includes following steps:
\enumerate{
\item An initial population Pt of a size N is created
\item A model is trained on each individual (subset) and fitness values are assigned
\item An offsping population of a size N is created by crossover and mutation operators
\item The offspring population is combined with its parent population
\item A combined population of a size 2N is split into Pareto Fronts using non-dominated
sorting technique
\item A next generation's population Pt+1 of size N is selected from the top Pareto Fronts
with help of elitism based selection operator
}
The loop is repeated until the final generation is reached

Each generation is populated by individuals representing different subsets.
Each individual is represented as a binary vector, where each gene represents
a feature in the original dataset.
}
\examples{
xgb_learner <- mlr::makeLearner("classif.xgboost", predict.type = "prob",
                            par.vals = list(
                            objective = "binary:logistic",
                            eval_metric = "error",nrounds = 2))

rsmp <- mlr::makeResampleDesc("CV", iters = 2)
measures <- list(mlr::mmce)

f_auc <- function(pred){auc <- mlr::performance(pred, auc)
                        return(as.numeric(auc))}
objective <- c(f_auc)
o_names <- c("AUC", "nf")
par <- rPref::high(AUC)*rPref::low(nf)

nsga3fs(df = german_credit, target = "BAD", obj_list = objective,
        obj_names = o_names, pareto = par, pop_size = 1, max_gen = 1,
        model = xgb_learner, resampling = rsmp,
        num_features = TRUE, r_measures = measures, cpus = 2)





}
\references{
K. Deb, H. Jain (2014) <DOI:10.1109/TEVC.2013.2281534>
}
