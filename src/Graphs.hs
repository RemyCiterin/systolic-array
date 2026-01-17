module Graphs where

import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.List as L
import GHC.Records(HasField(..))

-- This module define data flow graphs, those graphs are used to represent neural networks
-- in the early stage of the compilation (before scheduling and register allocation)

data Var = Var !Int deriving(Eq, Ord)

data App fn = App fn [Var] deriving(Eq, Ord)

-- A node in the graph is an equation of the form `x0 = f(x1, ..., xn)` with `x0`
-- the variable defined by the node, and `x1, ..., xn` the arguments of the function `f`.
-- A data-flow graph must be acyclic
data Graph fn =
  Graph
    { definitionMap :: M.Map Var (App fn)
    , successorsMap :: M.Map Var [Var]
    , nextVar :: Int }

definition :: Graph fn -> Var -> App fn
definition graph v = (graph.definitionMap) M.! v

instance HasField "definition" (Graph fn) (Var -> App fn) where
  getField graph = definition graph

successors :: Graph fn -> Var -> [Var]
successors graph v = (graph.successorsMap) M.! v

instance HasField "successors" (Graph fn) (Var -> [Var]) where
  getField graph = successors graph

instance Show Var where
  show (Var i) = "%" ++ show i

instance Show fn => Show (App fn) where
  show (App f args) = show f ++ " " ++ unwords (fmap show args)

variables :: Graph fn -> [Var]
variables graph = M.keys graph.definitionMap

instance HasField "variables" (Graph fn) [Var] where
  getField graph = variables graph

-- Add a new application into a graph, return the new graph and the unique variable
-- represented by this application
application :: App fn -> Graph fn -> (Var, Graph fn)
application app@(App _ args) graph =
  let var = Var graph.nextVar in
  ( var
  , Graph
    { definitionMap = M.insert var app graph.definitionMap
    , successorsMap =
      M.insert var [] $
        L.foldr
          (\ arg m -> M.insert arg (var : graph.successors arg) m)
          graph.successorsMap
          args
    , nextVar = graph.nextVar + 1 })

-- Remove a variable from the graph
delete :: Var -> Graph fn -> Graph fn
delete var graph =
  let App _ args = graph.definition var in
  graph
    { definitionMap = M.delete var graph.definitionMap
    , successorsMap =
      M.delete var $
        L.foldr
          (\ arg m -> M.insert arg (L.delete var (graph.successors arg)) m)
          graph.successorsMap
          args }

showGraph :: Show fn => Int -> Graph fn -> String
showGraph spaces graph = go graph.variables
  where
    go [] = ""
    go (var : vars) =
      take spaces (repeat ' ') ++ show var ++ " = " ++ show (graph.definition var) ++ "\n"
      ++ go vars

instance Show fn => Show (Graph fn) where
  show = showGraph 0

printGraph :: Show fn => Int -> Graph fn -> IO ()
printGraph spaces graph = putStrLn (showGraph spaces graph)
