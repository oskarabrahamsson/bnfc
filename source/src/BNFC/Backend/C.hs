{-# LANGUAGE NoImplicitPrelude #-}

{-
    BNF Converter: C Main file
    Copyright (C) 2004  Author:  Michael Pellauer

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA
-}
module BNFC.Backend.C (makeC) where

import Prelude'

import BNFC.Utils
import BNFC.CF
import BNFC.Options
import BNFC.Backend.Base
import BNFC.Backend.C.CFtoCAbs
import BNFC.Backend.C.CFtoFlexC
import BNFC.Backend.C.CFtoBisonC
import BNFC.Backend.C.CFtoCSkel
import BNFC.Backend.C.CFtoCPrinter
import BNFC.PrettyPrint
import Data.Char
import qualified BNFC.Backend.Common.Makefile as Makefile

makeC :: SharedOptions -> CF -> MkFiles ()
makeC opts cf = do
    let (hfile, cfile) = cf2CAbs prefix cf
    mkfile "Absyn.h" hfile
    mkfile "Absyn.c" cfile
    let (flex, env) = cf2flex prefix cf
    mkfile (name ++ ".l") flex
    let bison = cf2Bison prefix cf env
    mkfile (name ++ ".y") bison
    let header = mkHeaderFile cf (allCats cf) (allEntryPoints cf) env
    mkfile "Parser.h" header
    let (skelH, skelC) = cf2CSkel cf
    mkfile "Skeleton.h" skelH
    mkfile "Skeleton.c" skelC
    let (prinH, prinC) = cf2CPrinter cf
    mkfile "Printer.h" prinH
    mkfile "Printer.c" prinC
    mkfile "Test.c" (ctest cf)
    Makefile.mkMakefile opts (makefile name prefix)
  where prefix :: String  -- The prefix is a string used by flex and bison
                          -- that is prepended to generated function names.
                          -- In most cases we want the grammar name as the prefix
                          -- but in a few specific cases, this can create clashes
                          -- with existing functions
        prefix = if name `elem` ["m","c","re","std","str"]
                  then name ++ "_" else name
        name = lang opts


makefile :: String -> String -> String -> Doc
makefile name prefix basename = vcat
    [ "CC = gcc"
    , "CCFLAGS = -g -W -Wall"
    , ""
    , "FLEX = flex"
    , "FLEX_OPTS = -P" <> text prefix
    , ""
    , "BISON = bison"
    , "BISON_OPTS = -t -p" <> text prefix
    , ""
    , "OBJS = Absyn.o Lexer.o Parser.o Printer.o"
    , ""
    , Makefile.mkRule ".PHONY" ["clean", "distclean"]
      []
    , Makefile.mkRule "all" [testName]
      []
    , Makefile.mkRule "clean" []
      -- peteg: don't nuke what we generated - move that to the "vclean" target.
      [ "rm -f *.o " ++ testName ++ " " ++ unwords
        [ name ++ e | e <- [".aux", ".log", ".pdf",".dvi", ".ps", ""]] ]
    , Makefile.mkRule "distclean" ["clean"]
      [ "rm -f " ++ unwords
        [ "Absyn.h", "Absyn.c", "Test.c", "Parser.c", "Parser.h", "Lexer.c",
          "Skeleton.c", "Skeleton.h", "Printer.c", "Printer.h", basename,
          name ++ ".l", name ++ ".y", name ++ ".tex"
        ]
      ]
    , Makefile.mkRule testName ["${OBJS}", "Test.o"]
      [ "@echo \"Linking " ++ testName ++ "...\""
      , "${CC} ${CCFLAGS} ${OBJS} Test.o -o " ++ testName ]
    , Makefile.mkRule "Absyn.o" [ "Absyn.c", "Absyn.h"]
      [ "${CC} ${CCFLAGS} -c Absyn.c" ]
    , Makefile.mkRule "Lexer.c" [ name ++ ".l" ]
      [ "${FLEX} ${FLEX_OPTS} -oLexer.c " ++ name ++ ".l" ]
    , Makefile.mkRule "Parser.c" [ name ++ ".y" ]
      [ "${BISON} ${BISON_OPTS} " ++ name ++ ".y -o Parser.c" ]
    , Makefile.mkRule "Lexer.o" [ "Lexer.c", "Parser.h" ]
      [ "${CC} ${CCFLAGS} -c Lexer.c " ]
    , Makefile.mkRule "Parser.o" ["Parser.c", "Absyn.h" ]
      [ "${CC} ${CCFLAGS} -c Parser.c" ]
    , Makefile.mkRule "Printer.o" [ "Printer.c", "Printer.h", "Absyn.h" ]
      [ "${CC} ${CCFLAGS} -c Printer.c" ]
    , Makefile.mkRule "Test.o" [ "Test.c", "Parser.h", "Printer.h", "Absyn.h" ]
      [ "${CC} ${CCFLAGS} -c Test.c" ]
    ]
  where testName = "Test" ++ name

-- | Generate a test program that parses stdin and prints the AST and it's
-- linearization
ctest :: CF -> String
ctest cf =
  unlines
   [
    "/*** Compiler Front-End Test automatically generated by the BNF Converter ***/",
    "/*                                                                          */",
    "/* This test will parse a file, print the abstract syntax tree, and then    */",
    "/* pretty-print the result.                                                 */",
    "/*                                                                          */",
    "/****************************************************************************/",
    "",
    "#include <stdio.h>",
    "#include <stdlib.h>",
    "#include <string.h>",
    "",
    "#include \"Parser.h\"",
    "#include \"Printer.h\"",
    "#include \"Absyn.h\"",
    "",
    "void usage(void) {",
    "  printf(\"usage: Call with one of the following argument " ++
      "combinations:\\n\");",
    "  printf(\"\\t--help\\t\\tDisplay this help message.\\n\");",
    "  printf(\"\\t(no arguments)\tParse stdin verbosely.\\n\");",
    "  printf(\"\\t(files)\\t\\tParse content of files verbosely.\\n\");",
    "  printf(\"\\t-s (files)\\tSilent mode. Parse content of files " ++
      "silently.\\n\");",
    "}",
    "",
    "int main(int argc, char ** argv)",
    "{",
    "  FILE *input;",
    "  " ++ dat ++ " parse_tree;",
    "  int quiet = 0;",
    "  char *filename = NULL;",
    "",
    "  if (argc > 1) {",
    "    if (strcmp(argv[1], \"-s\") == 0) {",
    "      quiet = 1;",
    "      if (argc > 2) {",
    "        filename = argv[2];",
    "      } else {",
    "        input = stdin;",
    "      }",
    "    } else {",
    "      filename = argv[1];",
    "    }",
    "  }",
    "",
    "  if (filename) {",
    "    input = fopen(filename, \"r\");",
    "    if (!input) {",
    "      usage();",
    "      exit(1);",
    "    }",
    "  }",
    "  else input = stdin;",
    "  /* The default entry point is used. For other options see Parser.h */",
    "  parse_tree = p" ++ def ++ "(input);",
    "  if (parse_tree)",
    "  {",
    "    printf(\"\\nParse Successful!\\n\");",
    "    if (!quiet) {",
    "      printf(\"\\n[Abstract Syntax]\\n\");",
    "      printf(\"%s\\n\\n\", show" ++ dat ++ "(parse_tree));",
    "      printf(\"[Linearized Tree]\\n\");",
    "      printf(\"%s\\n\\n\", print" ++ dat ++ "(parse_tree));",
    "    }",
    "    return 0;",
    "  }",
    "  return 1;",
    "}",
    ""
   ]
  where
  cat :: Cat
  cat = head $ allEntryPoints cf
  def :: String
  def = identCat cat
  dat :: String
  dat = identCat . normCat $ cat

mkHeaderFile :: CF -> [Cat] -> [Cat] -> [(a, String)] -> String
mkHeaderFile cf cats eps env = unlines
 [
  "#ifndef PARSER_HEADER_FILE",
  "#define PARSER_HEADER_FILE",
  "",
  "#include \"Absyn.h\"",
  "",
  "typedef union",
  "{",
  "  int int_;",
  "  char char_;",
  "  double double_;",
  "  char* string_;",
  concatMap mkVar cats ++ "} YYSTYPE;",
  "",
  "#define _ERROR_ 258",
  mkDefines (259::Int) env,
  "extern YYSTYPE yylval;",
  concatMap mkFunc eps,
  "",
  "#endif"
 ]
 where
  mkVar s | (normCat s == s) = "  " ++ (identCat s) +++ (map toLower (identCat s)) ++ "_;\n"
  mkVar _ = ""
  mkDefines n [] = mkString n
  mkDefines n ((_,s):ss) = ("#define " ++ s +++ (show n) ++ "\n") ++ (mkDefines (n+1) ss)
  mkString n =  if isUsedCat cf catString
   then ("#define _STRING_ " ++ show n ++ "\n") ++ mkChar (n+1)
   else mkChar n
  mkChar n =  if isUsedCat cf catChar
   then ("#define _CHAR_ " ++ show n ++ "\n") ++ mkInteger (n+1)
   else mkInteger n
  mkInteger n =  if isUsedCat cf catInteger
   then ("#define _INTEGER_ " ++ show n ++ "\n") ++ mkDouble (n+1)
   else mkDouble n
  mkDouble n =  if isUsedCat cf catDouble
   then ("#define _DOUBLE_ " ++ show n ++ "\n") ++ mkIdent(n+1)
   else mkIdent n
  mkIdent n =  if isUsedCat cf catIdent
   then ("#define _IDENT_ " ++ show n ++ "\n")
   else ""
  -- Andreas, 2019-04-29, issue #210: generate parsers also for coercions
  mkFunc c = identCat (normCat c) ++ " p" ++ identCat c ++ "(FILE *inp);\n"
