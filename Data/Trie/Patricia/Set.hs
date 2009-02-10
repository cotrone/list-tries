-- File created: 2008-11-08 19:22:07

-- The base implementation of a Patricia trie representing a set of lists,
-- generalized over any type of map from element values to tries.
--
-- Complexities are given; @n@ refers to the number of elements in the set and
-- @m@ to their maximum length. In addition, the trie's branching factor plays
-- a part in almost every operation, but the complexity depends on the
-- underlying Map. Thus, for instance, 'member' is actually O(m f(b)) where
-- f(b) is the complexity of a lookup operation on the Map used. Because this
-- complexity depends on the underlying operation, which is visible only in the
-- source code and thus can be changed whilst affecting the complexity only for
-- certain Map types, this "b factor" is not shown explicitly.
--
-- Disclaimer: the complexities have not been proven.

{-# LANGUAGE CPP, MultiParamTypeClasses, FlexibleInstances
           , FlexibleContexts, UndecidableInstances #-}

#include "exports.h"

module Data.Trie.Patricia.Set (SET_EXPORTS) where

import Control.Arrow  ((***), second)
import Data.Function  (on)
import Data.Monoid    (Monoid(..))
import Prelude hiding (filter, foldr, map, null)
import qualified Prelude

#if __GLASGOW_HASKELL__
import Text.Read (readPrec, lexP, parens, prec, Lexeme(Ident))
#endif

import qualified Data.Trie.Base.Map      as Map
import qualified Data.Trie.Patricia.Base as Base
import Data.Trie.Base.Classes (Identity(..), Unwrappable(..))
import Data.Trie.Base.Map     (Map, OrdMap)
import Data.Trie.Util         ((.:), (.:.), both)

-- Invariant: any (Tr False _ _) has at least two children, all of which are
-- True or have a True descendant.
--
-- In order to avoid a lot of special casing it has to be the case that there's
-- only one way to represent a given trie. The above property makes sure of
-- that, so that, for instance, 'fromList ["foo"]' can only be 'Tr True "foo"
-- Map.empty', and not 'Tr False "fo" (Map.fromList [('o',Tr True ""
-- Map.empty)])'. Base.tryCompress is a function which takes care of this.
--
-- This Base stuff is needed just as in the non-Patricia version.
data TrieSetBase map a bool = Tr !bool ![a] !(CMap map a bool)
type CMap map a bool = map a (TrieSetBase map a bool)

newtype TrieSet map a = TS { unTS :: TrieSetBase map a Bool }

inTS :: (TrieSetBase map a Bool -> TrieSetBase nap b Bool)
     -> (TrieSet map a -> TrieSet nap b)
inTS f = TS . f . unTS

instance Map map k => Base.Trie TrieSetBase Identity map k where
   mkTrie = Tr . unwrap
   tParts (Tr b p m) = (Id b,p,m)

-- CMap contains TrieSetBase, not TrieSet, hence we must supply these instances
-- for TrieSetBase first
instance (Map map a, Eq (CMap map a Bool)) => Eq (TrieSetBase map a Bool) where
   Tr b1 p1 m1 == Tr b2 p2 m2 =
      b1 == b2 && and (zipWith (Map.eqCmp m1) p1 p2)
               && m1 == m2

instance (Eq (TrieSetBase map a Bool)) => Eq (TrieSet map a) where
   TS tr1 == TS tr2 = tr1 == tr2

instance (OrdMap map a, Ord (CMap map a Bool)) => Ord (TrieSetBase map a Bool)
 where
   compare (Tr b1 p1 m1) (Tr b2 p2 m2) =
      compare b1 b2 `mappend` mconcat (zipWith (Map.ordCmp m1) p1 p2)
                    `mappend` compare m1 m2

instance (Ord (TrieSetBase map a Bool)) => Ord (TrieSet map a) where
   compare (TS tr1) (TS tr2) = compare tr1 tr2

instance Map map a => Monoid (TrieSet map a) where
   mempty  = empty
   mappend = union
   mconcat = unions

instance (Map map a, Show a) => Show (TrieSet map a) where
   showsPrec p s = showParen (p > 10) $
      showString "fromList " . shows (toList s)

instance (Map map a, Read a) => Read (TrieSet map a) where
#if __GLASGOW_HASKELL__
   readPrec = parens $ prec 10 $ do
      Ident "fromList" <- lexP
      fmap fromList readPrec
#else
   readsPrec p = readParen (p > 10) $ \r -> do
      ("fromList", list) <- lex r
      (xs, rest) <- readsPrec (p+1) list
      [(fromList xs, rest)]
#endif

-- * Querying

-- O(1)
null :: Map map a => TrieSet map a -> Bool
null = Base.null . unTS

-- O(n). The number of elements in the set.
size :: Map map a => TrieSet map a -> Int
size = Base.size . unTS

-- O(m).
member :: Map map a => [a] -> TrieSet map a -> Bool
member = Base.member .:. unTS

-- O(m).
notMember :: Map map a => [a] -> TrieSet map a -> Bool
notMember = Base.notMember .:. unTS

-- O(min(n1,n2))
isSubsetOf :: Map map a => TrieSet map a -> TrieSet map a -> Bool
isSubsetOf = Base.isSubmapOfBy (&&) `on` unTS

-- O(min(n1,n2))
isProperSubsetOf :: Map map a => TrieSet map a -> TrieSet map a -> Bool
isProperSubsetOf = Base.isProperSubmapOfBy (&&) `on` unTS

-- * Construction

-- O(1)
empty :: Map map a => TrieSet map a
empty = TS Base.empty

-- O(1)
singleton :: Map map a => [a] -> TrieSet map a
singleton k = TS$ Base.singleton k True

-- O(m)
insert :: Map map a => [a] -> TrieSet map a -> TrieSet map a
insert k = inTS$ Base.insert k True

-- O(m)
delete :: Map map a => [a] -> TrieSet map a -> TrieSet map a
delete = inTS . Base.delete

-- * Combination

defaultUnion :: Bool -> Bool -> Bool
defaultUnion = error "TrieSet.union :: internal error"

-- O(min(n1,n2))
union :: Map map a => TrieSet map a -> TrieSet map a -> TrieSet map a
union = TS .: Base.unionWith defaultUnion `on` unTS

unions :: Map map a => [TrieSet map a] -> TrieSet map a
unions = TS . Base.unionsWith defaultUnion . Prelude.map unTS

-- O(min(n1,n2))
difference :: Map map a => TrieSet map a -> TrieSet map a -> TrieSet map a
difference = TS .: Base.differenceWith
                      (error "TrieSet.difference :: internal error")
                   `on` unTS

-- O(min(n1,n2))
intersection :: Map map a => TrieSet map a -> TrieSet map a -> TrieSet map a
intersection = TS .: Base.intersectionWith
                        (error "TrieSet.intersection :: internal error")
                     `on` unTS

-- * Filtering

-- O(n m)
filter :: Map map a => ([a] -> Bool) -> TrieSet map a -> TrieSet map a
filter p = inTS $ Base.filterWithKey (\k _ -> p k)

-- O(n m)
partition :: Map map a
          => ([a] -> Bool) -> TrieSet map a -> (TrieSet map a, TrieSet map a)
partition p = both TS . Base.partitionWithKey (\k _ -> p k) . unTS

-- O(m)
split :: OrdMap map a => [a] -> TrieSet map a -> (TrieSet map a, TrieSet map a)
split = both TS .: Base.split .:. unTS

-- O(m)
splitMember :: OrdMap map a
            => [a] -> TrieSet map a -> (TrieSet map a, Bool, TrieSet map a)
splitMember = (\(l,b,g) -> (TS l,unwrap b,TS g)) .: Base.splitLookup .:. unTS

-- * Mapping

-- O(n m)
map :: (Map map a, Map map b) => ([a] -> [b]) -> TrieSet map a -> TrieSet map b
map = inTS . Base.mapKeysWith Base.fromList

-- O(n)
mapIn :: (Map map a, Map map b) => (a -> b) -> TrieSet map a -> TrieSet map b
mapIn = inTS . Base.mapInKeysWith defaultUnion

-- * Folding

-- O(n)
foldr :: Map map a => ([a] -> b -> b) -> b -> TrieSet map a -> b
foldr f = Base.foldrWithKey (\k _ -> f k) .:. unTS

-- O(n)
foldrAsc :: OrdMap map a => ([a] -> b -> b) -> b -> TrieSet map a -> b
foldrAsc f = Base.foldrAscWithKey (\k _ -> f k) .:. unTS

-- O(n)
foldrDesc :: OrdMap map a => ([a] -> b -> b) -> b -> TrieSet map a -> b
foldrDesc f = Base.foldrDescWithKey (\k _ -> f k) .:. unTS

-- O(n)
foldl' :: Map map a => ([a] -> b -> b) -> b -> TrieSet map a -> b
foldl' f = Base.foldlWithKey' (\k _ -> f k) .:. unTS

-- O(n)
foldlAsc' :: OrdMap map a => ([a] -> b -> b) -> b -> TrieSet map a -> b
foldlAsc' f = Base.foldlAscWithKey' (\k _ -> f k) .:. unTS

-- O(n)
foldlDesc' :: OrdMap map a => ([a] -> b -> b) -> b -> TrieSet map a -> b
foldlDesc' f = Base.foldlDescWithKey' (\k _ -> f k) .:. unTS

-- * Conversion between lists

-- O(n)
toList :: Map map a => TrieSet map a -> [[a]]
toList = Prelude.map fst . Base.toList . unTS

-- O(n)
toAscList :: OrdMap map a => TrieSet map a -> [[a]]
toAscList = Prelude.map fst . Base.toAscList . unTS

-- O(n)
toDescList :: OrdMap map a => TrieSet map a -> [[a]]
toDescList = Prelude.map fst . Base.toDescList . unTS

-- O(n m)
fromList :: Map map a => [[a]] -> TrieSet map a
fromList = TS . Base.fromList . Prelude.map (flip (,) True)

-- * Min/max

-- O(m)
findMin :: OrdMap map a => TrieSet map a -> Maybe [a]
findMin = fmap fst . Base.findMin . unTS

-- O(m)
findMax :: OrdMap map a => TrieSet map a -> Maybe [a]
findMax = fmap fst . Base.findMax . unTS

-- O(m)
deleteMin :: OrdMap map a => TrieSet map a -> TrieSet map a
deleteMin = inTS Base.deleteMin

-- O(m)
deleteMax :: OrdMap map a => TrieSet map a -> TrieSet map a
deleteMax = inTS Base.deleteMax

-- O(m)
minView :: OrdMap map a => TrieSet map a -> (Maybe [a], TrieSet map a)
minView = (fmap fst *** TS) . Base.minView . unTS

-- O(m)
maxView :: OrdMap map a => TrieSet map a -> (Maybe [a], TrieSet map a)
maxView = (fmap fst *** TS) . Base.maxView . unTS

-- O(m)
findPredecessor :: OrdMap map a => TrieSet map a -> [a] -> Maybe [a]
findPredecessor = fmap fst .: Base.findPredecessor . unTS

-- O(m)
findSuccessor :: OrdMap map a => TrieSet map a -> [a] -> Maybe [a]
findSuccessor = fmap fst .: Base.findSuccessor . unTS

-- * Trie-only operations

-- O(s) where s is the input
addPrefix :: Map map a => [a] -> TrieSet map a -> TrieSet map a
addPrefix = TS .: Base.addPrefix .:. unTS

-- O(1)
splitPrefix :: Map map a => TrieSet map a -> ([a], TrieSet map a)
splitPrefix = second TS . Base.splitPrefix . unTS

-- O(m)
lookupPrefix :: Map map a => [a] -> TrieSet map a -> TrieSet map a
lookupPrefix = TS .: Base.lookupPrefix .:. unTS

-- * Visualization

showTrie :: (Show a, Map map a) => TrieSet map a -> ShowS
showTrie = Base.showTrieWith (\(Id b) -> showChar $ if b then 'X' else ' ')
         . unTS
