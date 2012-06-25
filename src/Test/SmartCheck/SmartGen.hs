module Test.SmartCheck.SmartGen
  ( Result(..)
  , iterateArb
  , extractResult
  , resultify
  , replace
  , iter
  ) where

import Test.SmartCheck.Types
import Test.SmartCheck.DataToTree

import qualified Test.QuickCheck.Gen as Q
import qualified Test.QuickCheck as Q hiding (Result)
import qualified Test.QuickCheck.Property as Q

import System.Random hiding (next)
import Data.List
import Data.Maybe
import Data.Tree
import Control.Monad

---------------------------------------------------------------------------------

-- | Possible results of iterateArb.
data Result a = FailedPreCond -- ^ Couldn't satisfy the precondition of a
                              -- QuickCheck property
              | FailedProp    -- ^ Failed the property
              | Result a      -- ^ Satisfied it, with the satisfying value
  deriving (Show, Read, Eq)

---------------------------------------------------------------------------------

-- | Make some samples no larger than maxSz of the same type as value a.
samples :: Q.Arbitrary a 
        => a   -- ^ unused; just to type arbitrary.
        -> Int -- ^ Number of tries.
        -> Int -- ^ Maximum size of the structure generated.
        -> IO [a]
samples _ i maxSz = do
  rnd0 <- newStdGen
  when (maxSz < 0) (errorMsg "samples: maxSize less than 0.")
  let ls = sort . take i $ randomRs (0, maxSz) rnd0 -- XXX better distribution?
  let rnds rnd = rnd1 : rnds rnd2 where (rnd1,rnd2) = split rnd
  let Q.MkGen m = Q.arbitrary
  -- Remember, m is a *function*, that takes a random generator (r) and a
  -- maxSize parameter (n).  We control size using the n parameter.  This is
  -- morally equivalent to using the resize function in QuickCheck.Gen.
  return [ (m r n) | (r,n) <- rnds rnd0 `zip` ls ]

---------------------------------------------------------------------------------

-- | Replace the hole in d indexed by idx with a bunch of random values, and
-- test the new d against the property.  Returns the first new d (the full d but
-- with the hole replaced) that succeeds.
iterateArb :: SubTypes a
           => a -> Idx -> Int -> Int
           -> (a -> Q.Property) -> IO (Result a)
iterateArb d idx tries sz prop = 
  case getAtIdx d idx of
    Nothing -> errorMsg "iterateArb 0"
    Just v  -> do rnds <- mkVals v
                  forM_ rnds (\a -> if isNothing $ replace d idx a
                                      then errorMsg "iterateArb 1"
                                      else return ())

                  let res = catMaybes $ map (replace d idx) rnds
                  -- Catch errors that shouldn't ever happen: this means that
                  -- there is probably a bad idx passed in.
                  when (length res /= length rnds) (errorMsg "iterateArb 1")
                  foldM (extractResult prop) FailedPreCond res
  where
                   
  mkVals SubT { unSubT = v } = do
    rnds <- samples v tries sz
    return $ map subT rnds

---------------------------------------------------------------------------------

-- | Must pass the precondition at least once to return either FailedProp or
-- Result.
extractResult :: (a -> Q.Property) -> Result a -> a -> IO (Result a)
extractResult _    r@(Result _) _ = return r
extractResult prop r            a = do
  res <- resultify prop a 
  let go = case Q.ok res of
             Nothing -> r -- Failed the precondition
             Just b  -> if Q.expect res 
                          then if b then Result a else FailedProp
                          else if b then FailedProp else Result a
  return go

---------------------------------------------------------------------------------

replace :: SubTypes a => a -> Idx -> SubT -> Maybe a
replace d idx SubT { unSubT = v } = replaceAtIdx d idx v

---------------------------------------------------------------------------------

-- | Make a QuickCheck Result by applying a property function to a value.
resultify :: (a -> Q.Property) -> a -> IO Q.Result
resultify prop a = do 
  Q.MkRose r _ <- res fs
  return r

  where
  Q.MkGen { Q.unGen = f } = prop a :: Q.Gen Q.Prop
  fs = Q.unProp $ f err err        :: Q.Rose Q.Result
  res = Q.protectRose . Q.reduceRose

  err = errorMsg "resultify: should not evaluate."

---------------------------------------------------------------------------------

type Next a b = a -> b -> Forest () -> Idx -> [Idx] -> IO (a, [Idx])
type Test a b = a -> Idx -> IO b

-- Do a breadth-first traversal of the data, trying to replace holes.  When we
-- find an index we can replace, add its index to the index list.  Recurse down
-- the structure, following subtrees that have *not* been replaced.
iter :: SubTypes a 
     => a                 -- ^ Failed value
     -> Test a b          -- ^ Test to use
     -> Next a b          -- ^ What to do after the test
     -> (a -> Q.Property) -- ^ Property
     -> Forest ()         -- ^ Just care about structure (size), not values
     -> Idx               -- ^ Starting index to extrapolate
     -> [Idx]             -- ^ List of generalized indices
     -> IO (a, [Idx])
iter d test next prop forest idx idxs = 
  if done then return (d, idxs)
     else if nextLevel 
            then iter' forest idx { level  = level idx + 1, column = 0 } idxs
            else do tries <- test d idx
                    next d tries forest idx idxs

  where
  -- Location is w.r.t. the forest, not the original data value.
  pts        = breadthLevels forest
  done       = length pts <= level idx
  nextLevel  = length (pts !! level idx) <= column idx
  iter'      = iter d test next prop 

---------------------------------------------------------------------------------
