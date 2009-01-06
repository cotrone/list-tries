-- File created: 2009-01-06 13:26:25

-- A map with lists of elements that can be compared for equality as keys,
-- based on a trie.

{-# LANGUAGE CPP #-}

#include "exports.h"

module Data.Trie.Map.Eq (MAP_EXPORTS) where

import Data.Trie.Base.Map   (AList)
import Data.Trie.Map hiding (TrieMap)
import qualified Data.Trie.Map as Base
import Prelude hiding (filter, foldr, lookup, map, null)

type TrieMap = Base.TrieMap AList
