{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DeriveGeneric #-}

-- | Try to generate a very large counterexample.

module Main where

#if defined(qcjh) || defined(qcNone) || defined(qc10) || defined(qc20) || defined(feat) || defined(qcGen) || defined(smart) || defined(small)
import Test
import System.Environment
#endif

import Test.SmartCheck
import Test.QuickCheck
#ifdef small
import Test.LazySmallCheck hiding (Property, test, (==>))
import qualified Test.LazySmallCheck as S
#endif

import GHC.Generics hiding (P, C)
import Data.Typeable

import Data.Int
import Control.Monad

#ifdef feat
import Test.Feat
#endif

-----------------------------------------------------------------

#if defined(qcjh) || defined(qcNone) || defined(qc10) || defined(qc20)
-- So that Int16s aren't shrunk by default arbitrary instances.
newtype J = J { getInt :: Int16 } deriving (Show, Read)
type I = [J]
instance Arbitrary J where
  arbitrary = fmap J arbitrary
#else
type I = [Int16]
#endif

data T = T I I I I I
  deriving (Read, Show, Typeable, Generic)

-- SmallCheck --------------------------
#ifdef small
enum :: (Enum b, Integral a, Num b) => a -> [b]
enum d = [(-d')..d']
  where d' = fromIntegral d

instance Serial Int16 where
  series = drawnFrom . enum

instance Serial Word8 where
  series = drawnFrom . enum

instance Serial T where
  series = cons5 T
#endif
-- SmallCheck --------------------------

-- SmartCheck --------------------------
#ifdef smart
instance SubTypes I
instance SubTypes T
#endif
-- SmartCheck --------------------------

-- qc/shrink takes over 1m seconds
instance Arbitrary T where
#ifdef feat
  arbitrary = sized uniform
#else
  arbitrary = liftM5 T arbitrary arbitrary
                       arbitrary arbitrary arbitrary
#endif

#if defined(qcNone) || defined(feat)
  shrink _ = []
#endif
#if defined(qcjh)
  shrink (T i0 i1 i2 i3 i4) = map go xs
    where xs = shrink (i0, i1, i2, i3, i4)
          go (i0', i1', i2', i3', i4') = T i0' i1' i2' i3' i4'
#endif
#if defined(qc10) || defined(qc20)
  shrink (T i0 i1 i2 i3 i4) =
    [ T a b c d e | a <- tk i0
                  , b <- tk i1, c <- tk i2
                  , d <- tk i3, e <- tk i4 ]
    where
#ifdef qc10
    sz = 10
#endif
#ifdef qc20
    sz = 20
#endif
    tk x = take sz (shrink x)
#endif
#if defined(qcNaive)
  shrink (T i0 i1 i2 i3 i4) =
    [ T a b c d e | a <- shrink i0
                  , b <- shrink i1, c <- shrink i2
                  , d <- shrink i3, e <- shrink i4 ]
#endif
#if defined(qcGen)
  shrink = genericShrink
#endif

-- Feat --------------------------------
#ifdef feat
deriveEnumerable ''T
#endif
-- Feat --------------------------------

toList :: T -> [[Int16]]
toList (T i0 i1 i2 i3 i4) =
#if defined(qcjh) || defined(qcNone) || defined(qc10) || defined(qc20)
  (map . map) (fromIntegral . getInt) [i0, i1, i2, i3, i4]
#else
  [i0, i1, i2, i3, i4]
#endif


pre :: T -> Bool
pre t = all ((< 256) . sum) (toList t)

post :: T -> Bool
post t = (sum . concat) (toList t) < 5 * 256

prop :: T -> Property
prop t = pre t ==> post t

-- Smallcheck --------------------------
#ifdef small
prop_small :: T -> Bool
prop_small t = pre t S.==> post t
#endif
-- Smallcheck --------------------------

--------------------------------------------------------------------------------
-- Testing
--------------------------------------------------------------------------------

size :: T -> Int
size t = sum $ map length (toList t)

#if defined(qcjh) || defined(qcNone) || defined(qc10) || defined(qc20) || defined(feat) || defined(qcGen) || defined(smart) || defined(small)
main :: IO ()
main = do
  [file', rnds'] <- getArgs
  let rnds = read rnds' :: Int
  let file  = read file' :: String
#ifdef feat
  test file rnds $ runQC' proxy stdArgs {maxSuccess = 10000} prop size
#endif
#ifdef smart
  test file rnds $ runSC scStdArgs prop size
#endif
#if defined(qcNone) || defined(qc10) || defined(qc20) || defined(qcjh) || defined(qcNaive) || defined(qcGen)
  test file rnds $ runQC' proxy stdArgs prop size
#endif
#endif

#ifdef smart
-- Tester (not part of the benchmark).
smtChk :: IO ()
smtChk = smartCheck scStdArgs { scMaxForall = 20
                              , runForall   = True
                              , scMinForall = 25
                              , format = PrintString
                              } prop
#endif

