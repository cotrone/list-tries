-- File created: 2009-01-09 13:57:13

{-# LANGUAGE EmptyDataDecls, PatternGuards, TemplateHaskell #-}

module Tests.TH
   ( Module(..)
   , ListElemType, TrieType
   , makeFunc, makeTests
   ) where

import Control.Arrow ((***))
import Data.Maybe    (isJust)
import Language.Haskell.TH
   ( Exp(..), Lit(..), Stmt(..), Dec(..), Type(..), Clause(..), Pat(..)
   , Guard(..), Body(..), Match(..)
   , Q, ExpQ
   , Name, nameBase, mkName
   )

data Module = SetModule String | MapModule String

moduleName :: Module -> String
moduleName (SetModule m) = m
moduleName (MapModule m) = m

--data KeyType
--data ElemType
data ListElemType
data TrieType

keyType  = ''Char
elemType = ''Int

replaceTypes :: Module -> Type -> Type
replaceTypes m (ForallT names cxt t) = ForallT names cxt (replaceTypes m t)
replaceTypes m (AppT t1 t2) = AppT (replaceTypes m t1) (replaceTypes m t2)
--replaceTypes _ (ConT t) | t == ''KeyType  = ConT keyType
--replaceTypes _ (ConT t) | t == ''ElemType = ConT elemType
replaceTypes m (ConT t) | t == ''ListElemType =
   case m of
        SetModule _ -> ListT `AppT` ConT keyType
        MapModule _ -> (TupleT 2 `AppT` (ListT `AppT` ConT keyType))
                                 `AppT` (ConT elemType)

replaceTypes m (ConT t) | t == ''TrieType =
   case m of
        SetModule m' -> ConT (mkName $ m' ++ ".TrieSet") `AppT` ConT keyType
        MapModule m' -> ConT (mkName $ m' ++ ".TrieMap") `AppT` ConT keyType `AppT` ConT elemType
replaceTypes _ x = x

-- Given, say:
--    [SetModule "S", MapModule "M"]
--    [("x",Just (AppT (TupleT 2) (ConT Int) (ConT TrieType)))]
--    [d| f x y = x |]
--
-- generate: [d| f_S y = S.x  :: (Int,S.TrieSet Char)
--               f_M y = S2.x :: (Int,M.TrieMap Char Int)
--             |]
--
-- WARNING: shadowing names will break this! For instance the following:
--
--   f x y = let x = y in x
--
-- will result in:
--
--   f_S y = let x = y in S.x
--
-- Which is obviously very different in terms of semantics.
--
-- (Yes, this could be handled properly but I couldn't be bothered.)
makeFunc :: [Module] -> [(String, Maybe Type)] -> Q [Dec] -> Q [Dec]
makeFunc modules expands =
   let expandFuns = map expandTopDec modules
    in fmap (\decs -> concat [map f decs | f <- expandFuns])
 where
   isExpandable n = nameBase n `elem` map fst expands
   expandName n = nameBase n `lookup` expands

   expandTopDec modu (FunD name clauses) =
      FunD (modularName (nameBase name) (moduleName modu))
           (map (expandClause modu) clauses)
   expandTopDec _ _ =
      error "expandTopDec :: shouldn't ever see this declaration type"

   expandDec modu (FunD name clauses) =
      FunD name (map (expandClause modu) clauses)
   expandDec modu (ValD pat body decs) =
      ValD pat (expandBody modu body) (map (expandDec modu) decs)
   expandDec _ x@(SigD _ _) = x
   expandDec _ _ =
      error "expandDec :: shouldn't ever see this declaration type"

   expandClause modu (Clause pats body decs) =
      Clause (concatMap clearPat pats)
             (expandBody modu body)
             (map (expandDec modu) decs)

   -- Remove matching ones from the function arguments
   clearPat (VarP n) | isExpandable n = []
   clearPat x = [x]

   expandBody modu (NormalB expr)    = NormalB (expandE modu expr)
   expandBody modu (GuardedB guards) =
      GuardedB (map (expandGuard modu *** expandE modu) guards)

   expandE m (VarE n) | Just t <- expandName n = qualify VarE m t n
   expandE m (ConE n) | Just t <- expandName n = qualify ConE m t n
   expandE m (AppE e1 e2)         = AppE (expandE m e1) (expandE m e2)
   expandE m (InfixE me1 e me2)   = InfixE (fmap (expandE m) me1)
                                           (expandE m e)
                                           (fmap (expandE m) me2)
   expandE m (LamE pats e)        = LamE pats (expandE m e)
   expandE m (TupE es)            = TupE (map (expandE m) es)
   expandE m (CondE e1 e2 e3)     = CondE (expandE m e1)
                                          (expandE m e2)
                                          (expandE m e3)
   expandE m (LetE decs e)        = LetE (map (expandDec m) decs) (expandE m e)
   expandE m (CaseE e matches)    = CaseE (expandE m e)
                                          (map (expandMatch m) matches)
   expandE m (DoE stmts)          = DoE (map (expandStmt m) stmts)
   expandE m (CompE stmts)        = CompE (map (expandStmt m) stmts)
   expandE m (SigE e t)           = SigE (expandE m e) t
   expandE m (RecConE name fexps) = RecConE name (map (expandFieldExp m) fexps)
   expandE m (RecUpdE name fexps) = RecUpdE name (map (expandFieldExp m) fexps)
   expandE _ x = x

   qualify expr modu mtyp name =
      let expr' = expr $ mkName (moduleName modu ++ "." ++ nameBase name)
       in case mtyp of
               Just typ -> SigE expr' (replaceTypes modu typ)
               Nothing  -> expr'

   expandMatch modu (Match pat body decs) =
      Match pat (expandBody modu body) (map (expandDec modu) decs)

   expandStmt modu (BindS pat expr) = BindS pat (expandE modu expr)
   expandStmt modu (LetS decs)      = LetS (map (expandDec modu) decs)
   expandStmt modu (NoBindS expr)   = NoBindS (expandE modu expr)
   expandStmt _    (ParS _)         = error "expandStmt :: ParS? What's that?"

   expandFieldExp modu (name,expr) = (name, expandE modu expr)

   expandGuard modu (NormalG expr) = NormalG (expandE modu expr)
   expandGuard modu (PatG stmts)   = PatG (map (expandStmt modu) stmts)

makeTests :: [Module] -> String -> String -> ExpQ
makeTests modules test testName =
   return.ListE $
      map (\m -> let mn = moduleName m
                     n  = modularName test mn
                  in VarE (mkName "testProperty") `AppE`
                     LitE (StringL (testName ++ "-" ++ lastPart mn)) `AppE`
                     VarE n)
          modules
 where
   lastPart = until (notElem '.') (tail.dropWhile (/='.'))

modularName :: String -> String -> Name
modularName name modu =
   mkName $ name ++ "_" ++ map (\c -> if c == '.' then '_' else c) modu