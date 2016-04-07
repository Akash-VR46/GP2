module Main where

import System.IO
import System.Environment
import System.Console.GetOpt
import System.Process (system)
import System.Exit

import Text.Parsec
import Data.List

import OILR4.Instructions
import OILR4.HostCompile
import OILR4.Config
import OILR4.IR
import OILR4.Optimiser
import OILR4.OILROptim
import OILR4.X86Backend
import OILR4.CBackend


-- import GPSyntax -- debug code
import ParseGraph
import ParseProgram
import ProcessAst (makeHostGraph)

options :: [ OptDescr Flag ]
options = [ Option ['O'] ["no-oilr"] (NoArg NoOILR)
                    "Use only a single OILR index for all nodes.",
            Option ['M'] ["no-sort"] (NoArg NoMatchSort)
                    "Don't sort rule nodes most-constrained-first",
            Option ['P'] ["no-plan"] (NoArg NoSearchPlan)
                    "Disable the search plan; use brute-force nodes-then-edges strategy",
            Option ['R'] ["no-recursive"] (NoArg NoRecursion)
                    "Disable recursive looped rule optimisation.",

            Option ['D'] ["dump"] (ReqArg Dump "TYPE")
                    "Don't compile; dump code to stdout. Valid options: c, oilr, ir",
            Option ['3'] ["32-bit"]  (NoArg Compile32Bit)
                    "Compile a 32-bit executable" ,

            Option ['d'] ["debug"]   (NoArg EnableDebugging)
                    "Enable verbose debugging output on compiled program's stderr" ,
            Option ['e'] ["extra-debug"]   (NoArg EnableParanoidDebugging)
                    "Enable paranoid graph structure checks (implies -d)",
            Option ['t'] ["trace"]   (NoArg EnableExecutionTrace)
                    "Enable execution trace" ]


debugCompiler = "gcc -g "
perfCompiler  = "gcc -O2 "

compilerFlagsCommon = "-Wno-format -Wno-unused-label -Wall -Wextra -Werror -m32 -o "

getCompilerFor flags = concat [ cc, compilerFlagsCommon ]
    where
        cc = if ( EnableDebugging `elem` flags || EnableParanoidDebugging `elem` flags)
                then debugCompiler
                else perfCompiler

getStem :: String -> String
getStem = takeWhile (/= '.')

parseHostGraph graphFile = do
    g <- readFile graphFile
    case parse hostGraph graphFile g of
        Left e     -> error $ "Compilation of host graph failed" ++ show e
        Right host -> return $ makeHostGraph host

parseProgram progFile = do
    p <- readFile progFile
    case parse program progFile p of
        Left e     -> error $ "Compilation of program failed:\n" ++ show e
        Right prog -> return prog

callCCompiler cc obj cFile = do
    -- TODO: use of system is ugly and potentially dangerous!
    exStatus <- system $ intercalate " " [cc, obj, cFile]
    case exStatus of
        ExitSuccess -> return ()
        (ExitFailure _) -> error "Compilation failed."


main = do
    hSetBuffering stdout NoBuffering
    args <- getArgs
    case getOpt Permute options args of
        (flags, [progFile, hostFile], []) -> do
            let stem = getStem progFile
            let targ = stem ++ ".c"
            let exe  = stem
            -- p <- readFile progFile
            pAST <- parseProgram progFile
            hAST <- parseHostGraph hostFile
            let ir = makeIR pAST
            let cf = configureOilrMachine flags ir
            let (cf', prog) = compileProg cf $ optimise cf ir
            let c = compileC cf' prog
            -- let host = compileHostGraph hAST
            -- putStrLn $ show prog
            let compiler = getCompilerFor flags
            case find (\f -> case f of { Dump _ -> True; _ -> False }) flags of
                Just (Dump "ir")   -> putStrLn $ prettyIR ir
                Just (Dump "oilr") -> putStrLn $ prettyProg prog
                Just (Dump "c")    -> putStrLn c
                Just (Dump s)      -> error $ s ++ " is not a valid option to --dump."
                Nothing            -> do writeFile targ $ c
                                         putStrLn $ intercalate " " [compiler,exe,targ]
                                         callCCompiler compiler exe targ
                     -- return ()
        _ -> do
            error "Nope"

