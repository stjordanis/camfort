{-
   Copyright 2016, Dominic Orchard, Andrew Rice, Mistral Contrastin, Matthew Danish

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}

{- This module collects together stubs that connect analysis/transformations
   with the input -> output procedures -}

{-# LANGUAGE ImplicitParams, DoAndIfThenElse #-}

module Camfort.Functionality where

import System.Console.GetOpt
import System.Directory
import System.Environment
import System.IO

import Data.Monoid
import Data.Generics.Uniplate.Operations

import Camfort.Analysis.Annotations
import Camfort.Analysis.Types
import Camfort.Analysis.Loops
import Camfort.Analysis.LVA
import Camfort.Analysis.Syntax

import Camfort.Transformation.DeadCode
import Camfort.Transformation.CommonBlockElim
import Camfort.Transformation.CommonBlockElimToCalls
import Camfort.Transformation.EquivalenceElim
import Camfort.Transformation.DerivedTypeIntro

import Camfort.Extensions.Units as LU
import Camfort.Extensions.UnitSyntaxConversion
import Camfort.Extensions.UnitsEnvironment
import Camfort.Extensions.UnitsSolve

import Camfort.Helpers
import Camfort.Output
import Camfort.Input

import Data.List (foldl', nub, (\\), elemIndices, intersperse, intercalate)

-- FORPAR
import qualified Language.Fortran.Parser.Fortran77 as F77
import qualified Language.Fortran.AST as A
import Language.Fortran.Analysis.Renaming
  (renameAndStrip, analyseRenames, unrename, NameMap)
import Language.Fortran.Analysis(initAnalysis)
import Camfort.Extensions.UnitsForpar
import qualified Camfort.Analysis.StencilSpecification as StencilsForpar

-- * Wrappers on all of the features
typeStructuring inSrc excludes outSrc _ = do
    putStrLn $ "Introducing derived data types in " ++ show inSrc ++ "\n"
    doRefactor typeStruct inSrc excludes outSrc

ast d _ f _ = do
    (_, _, p) <- readParseSrcFile (d ++ "/" ++ f)
    putStrLn $ show p

asts inSrc excludes _ _ = do
    putStrLn $ "Do a basic analysis and output the HTML files"
            ++ "with AST information for " ++ show inSrc ++ "\n"
    let astAnalysis = (map numberStmts) . map (fmap (const unitAnnotation))
    doAnalysis astAnalysis inSrc excludes

countVarDecls inSrc excludes _ _ = do
    putStrLn $ "Counting variable declarations in " ++ show inSrc ++ "\n"
    doAnalysisSummary countVariableDeclarations inSrc excludes

loops inSrc excludes _ _ = do
    putStrLn $ "Analysing loops for " ++ show inSrc ++ "\n"
    doAnalysis loopAnalyse inSrc excludes

lvaA inSrc excludes _ _ = do
    putStrLn $ "Analysing loops for " ++ show inSrc ++ "\n"
    doAnalysis lva inSrc excludes

dead inSrc excludes outSrc _ = do
    putStrLn $ "Eliminating dead code in " ++ show inSrc ++ "\n"
    doRefactor ((mapM (deadCode False))) inSrc excludes outSrc

commonToArgs inSrc excludes outSrc _ = do
    putStrLn $ "Refactoring common blocks in " ++ show inSrc ++ "\n"
    doRefactor (commonElimToCalls inSrc) inSrc excludes outSrc

common inSrc excludes outSrc _ = do
    putStrLn $ "Refactoring common blocks in " ++ show inSrc ++ "\n"
    doRefactor (commonElimToModules inSrc) inSrc excludes outSrc

equivalences inSrc excludes outSrc _ = do
    putStrLn $ "Refactoring equivalences blocks in " ++ show inSrc ++ "\n"
    doRefactor (mapM refactorEquivalences) inSrc excludes outSrc

{- Units feature -}
units inSrc excludes outSrc opt = do
    putStrLn $ "Inferring units for " ++ show inSrc ++ "\n"
    let ?solver = solverType opt
     in let ?assumeLiterals = literalsBehaviour opt
        in doRefactor' (mapM LU.inferUnits) inSrc excludes outSrc

unitCriticals inSrc excludes outSrc opt = do
    putStrLn $ "Infering critical variables for units inference in directory "
             ++ show inSrc ++ "\n"
    let ?solver = solverType opt
     in let ?assumeLiterals = literalsBehaviour opt
        in doAnalysisReport' (mapM LU.inferCriticalVariables)
              inSrc excludes outSrc

stencilsInf inSrc excludes _ _ = do
  putStrLn $ "Inferring stencil specs for " ++ show inSrc ++ "\n"
  doAnalysisSummaryForpar StencilsForpar.infer inSrc excludes

stencilsCheck inSrc excludes _ _ = do
  putStrLn $ "Checking stencil specs for " ++ show inSrc ++ "\n"
  doAnalysis StencilsForpar.check inSrc excludes

stencilsVarFlowCycles inSrc excludes _ _ = do
  putStrLn $ "Inferring var flow cycles for " ++ show inSrc ++ "\n"
  let flowAnalysis = intercalate ", " . map show . StencilsForpar.findVarFlowCycles
  doAnalysisSummaryForpar flowAnalysis inSrc excludes

--------------------------------------------------
-- Forpar wrappers

doRefactorForpar :: ([(Filename, A.ProgramFile A)]
                 -> (String, [(Filename, A.ProgramFile Annotation)]))
                 -> FileOrDir -> [Filename] -> FileOrDir -> IO ()
doRefactorForpar rFun inSrc excludes outSrc = do
    if excludes /= [] && excludes /= [""]
    then putStrLn $ "Excluding " ++ (concat $ intersperse "," excludes)
           ++ " from " ++ inSrc ++ "/"
    else return ()
----
    ps <- readForparseSrcDir inSrc excludes
    let (report, ps') = rFun (map (\(f, inp, ast) -> (f, ast)) ps)
    --let outFiles = filter (\f -not ((take (length $ d ++ "out") f) == (d ++ "out"))) (map fst ps')
    let outFiles = map fst ps'
    putStrLn report
    -- outputFiles inSrc outSrc (zip3 outFiles (map Fortran.snd3 ps ++ (repeat "")) (map snd ps'))
----

{-| Performs an analysis which reports to the user,
     but does not output any files -}
doAnalysisReportForpar :: ([(Filename, A.ProgramFile A)] -> (String, t1))
                       -> FileOrDir -> [Filename] -> t -> IO ()
doAnalysisReportForpar rFun inSrc excludes outSrc = do
  if excludes /= [] && excludes /= [""]
      then putStrLn $ "Excluding " ++ (concat $ intersperse "," excludes)
                    ++ " from " ++ inSrc ++ "/"
      else return ()
  ps <- readForparseSrcDir inSrc excludes
----
  putStr "\n"
  let (report, ps') = rFun (map (\(f, inp, ast) -> (f, ast)) ps)
  putStrLn report
----

-- * Source directory and file handling
readForparseSrcDir :: FileOrDir -> [Filename]
                   -> IO [(Filename, SourceText, A.ProgramFile A)]
readForparseSrcDir inp excludes = do
    isdir <- isDirectory inp
    files <- if isdir
             then do files <- rGetDirContents inp
                     return $ (map (\y -> inp ++ "/" ++ y) files) \\ excludes
             else return [inp]
    mapM readForparseSrcFile files
----

{-| Read a specific file, and parse it -}
readForparseSrcFile :: Filename -> IO (Filename, SourceText, A.ProgramFile A)
readForparseSrcFile f = do
    putStrLn f
    inp <- readFile f
    let ast = forparse inp f
    return $ (f, inp, fmap (const unitAnnotation) ast)
----

{-| parse file into an un-annotated Fortran AST -}
forparse :: SourceText -> Filename -> A.ProgramFile ()
forparse contents f = F77.fortran77Parser contents f


doAnalysisSummaryForpar :: (Monoid s, Show' s) => (A.ProgramFile A -> s)
                        -> FileOrDir -> [Filename] -> IO ()
doAnalysisSummaryForpar aFun inSrc excludes = do
  if excludes /= [] && excludes /= [""]
    then putStrLn $ "Excluding " ++ (concat $ intersperse "," excludes)
                                 ++ " from " ++ inSrc ++ "/"
    else return ()
  ps <- readForparseSrcDir inSrc excludes
  let inFiles = map (\(a, _, _) -> a) ps
  putStrLn "Output of the analysis:"
  putStrLn . show' $ foldl' (\n (f, _, ps) -> n `mappend` (aFun ps)) mempty ps

-- Custom 'Show' which on strings is the identity
class Show' s where
      show' :: s -> String
instance Show' String where
      show' = id
instance Show' Int where
      show' = show