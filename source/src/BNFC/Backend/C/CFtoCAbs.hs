{-# LANGUAGE NoImplicitPrelude #-}

{-
    BNF Converter: C Abstract syntax
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

{-
   **************************************************************
    BNF Converter Module

    Description   : This module generates the C Abstract Syntax
                    tree classes. It generates both a Header file
                    and an Implementation file, and Appel's C
                    method.

    Author        : Michael Pellauer (pellauer@cs.chalmers.se)

    License       : GPL (GNU General Public License)

    Created       : 15 September, 2003

    Modified      : 15 September, 2003


   **************************************************************
-}

module BNFC.Backend.C.CFtoCAbs (cf2CAbs) where

import Prelude'

import BNFC.CF
import BNFC.PrettyPrint
import BNFC.Utils((+++))
import BNFC.Backend.Common.NamedVariables
import Data.Function (on)
import Data.List
import Data.Char(toLower)


-- | The result is two files (.H file, .C file)
cf2CAbs
  :: String -- ^ Ignored.
  -> CF     -- ^ Grammar.
  -> (String, String) -- ^ @.H@ file, @.C@ file.
cf2CAbs _ cf = (mkHFile cf, mkCFile cf)

{- **** Header (.H) File Functions **** -}

-- | Makes the Header file.

mkHFile :: CF -> String
mkHFile cf = unlines
    [ "#ifndef ABSYN_HEADER"
    , "#define ABSYN_HEADER"
    , ""
    , header
    , prTypeDefs user
    , "/********************   Forward Declarations    ********************/\n"
    , concatMap prForward classes
    , ""
    , "/********************   Abstract Syntax Classes    ********************/\n"
    , concatMap prDataH (getAbstractSyntax cf)
    , ""
    , "#endif"
    ]
  where
  user = fst (unzip (tokenPragmas cf))
  header = "/* C++ Abstract Syntax Interface generated by the BNF Converter.*/\n"
  rules :: [String]
  rules = getRules cf
  classes = nub (rules ++ getClasses (allCatsNorm cf))
  prForward s | not (isCoercion s) = unlines
    [ "struct " ++ s ++ "_;"
    , "typedef struct " ++ s ++ "_ *" ++ s ++ ";"
    ]
  prForward _ = ""
  getRules cf = map testRule (cfgRules cf)
  getClasses = map show . filter isDataCat
  testRule (Rule f c _)
    | isList c && isConsFun f = identCat (normCat c)
    | otherwise = "_"

-- | Prints struct definitions for all categories.
prDataH :: Data -> String
prDataH (cat, rules)
  | isList cat = unlines
      [ "struct " ++ c' ++ "_"
      , "{"
      , "  " ++ mem +++ varName mem ++ ";"
      , "  " ++ c' +++ varName c' ++ ";"
      , "};"
      , ""
      , c' ++ " make_" ++ c' ++ "(" ++ mem ++ " p1, " ++ c' ++ " p2);"
      ]
  | otherwise = unlines
      [ "struct " ++ show cat ++ "_"
      , "{"
      , "  enum { " ++ intercalate ", " (map prKind rules) ++ " } kind;"
      , "  union"
      , "  {"
      , concatMap prUnion rules ++ "  } u;"
      , "};"
      , ""
      , concatMap (prRuleH cat) rules
      ]
  where
    c' = identCat (normCat cat)
    mem = identCat (normCatOfList cat)
    prKind (fun, _) = "is_" ++ fun
    prUnion (_, []) = ""
    prUnion (fun, cats) = "    struct { " ++ (render $ prInstVars (getVars cats)) ++ " } " ++ (memName fun) ++ ";\n"


-- | Interface definitions for rules vary on the type of rule.
prRuleH :: Cat -> (Fun, [Cat]) -> String
prRuleH c (fun, cats) =
    if isNilFun fun || isOneFun fun || isConsFun fun
    then ""  --these are not represented in the AbSyn
    else --a standard rule
      show c ++ " make_" ++ fun ++ "(" ++ (prParamsH 0 (getVars cats)) ++ ");\n"
  where
    prParamsH :: Int -> [(String, a)] -> String
    prParamsH _ [] = "void"
    prParamsH n ((t,_):[]) = t ++ " p" ++ (show n)
    prParamsH n ((t,_):vs) = (t ++ " p" ++ (show n) ++ ", ") ++ (prParamsH (n+1) vs)

-- typedefs in the Header make generation much nicer.
prTypeDefs user = unlines
    [ "/********************   TypeDef Section    ********************/"
    , "typedef int Integer;"
    , "typedef char Char;"
    , "typedef double Double;"
    , "typedef char* String;"
    , "typedef char* Ident;"
    , concatMap prUserDef user
    ]
  where
    prUserDef s = "typedef char* " ++ show s ++ ";\n"

-- | A class's instance variables. Print the variables declaration by grouping
-- together the variables of the same type.
-- >>> prInstVars [("A", 1)]
-- A a_1;
-- >>> prInstVars [("A",1),("A",2),("B",1)]
-- A a_1, a_2; B b_1;
prInstVars :: [IVar] -> Doc
prInstVars =
    hsep . map prInstVarsOneType . groupBy ((==) `on` fst) . sort
  where
    prInstVarsOneType ivars = text (fst (head ivars))
                              <+> hsep (punctuate comma (map prIVar ivars))
                              <> semi
    prIVar (s, i) = text (varName s) <> text (showNum i)

{- **** Implementation (.C) File Functions **** -}

-- | Makes the .C file
mkCFile :: CF -> String
mkCFile cf = unlines
  [ header
  , concatMap (render . prDataC) (getAbstractSyntax cf)
  ]
  where
  header = unlines
    [ "/* C Abstract Syntax Implementation generated by the BNF Converter. */"
    , ""
    , "#include <stdio.h>"
    , "#include <stdlib.h>"
    , "#include \"Absyn.h\""
    , ""
    ]

prDataC :: Data -> Doc
prDataC (cat, rules) = vcat' $ map (prRuleC cat) rules

-- | Classes for rules vary based on the type of rule.
--
-- * Empty list constructor, these are not represented in the AbSyn
-- >>> prRuleC (ListCat (Cat "A")) ("[]", [Cat "A", Cat "B", Cat "B"])
-- <BLANKLINE>
--
-- * Linked list case. These are all built-in list functions.
-- Later we could include things like lookup, insert, delete, etc.
-- >>> prRuleC (ListCat (Cat "A")) ("(:)", [Cat "A", Cat "B", Cat "B"])
-- /********************   ListA    ********************/
-- ListA make_ListA(A p1, ListA p2)
-- {
--     ListA tmp = (ListA) malloc(sizeof(*tmp));
--     if (!tmp)
--     {
--         fprintf(stderr, "Error: out of memory when allocating ListA!\n");
--         exit(1);
--     }
--     tmp->a_ = p1;
--     tmp->lista_ = p2;
--     return tmp;
-- }
--
-- * Standard rule
-- >>> prRuleC (Cat "A") ("funa", [Cat "A", Cat "B", Cat "B"])
-- /********************   funa    ********************/
-- A make_funa(A p1, B p2, B p3)
-- {
--     A tmp = (A) malloc(sizeof(*tmp));
--     if (!tmp)
--     {
--         fprintf(stderr, "Error: out of memory when allocating funa!\n");
--         exit(1);
--     }
--     tmp->kind = is_funa;
--     tmp->u.funa_.a_ = p1;
--     tmp->u.funa_.b_1 = p2;
--     tmp->u.funa_.b_2 = p3;
--     return tmp;
-- }
prRuleC :: Cat -> (String, [Cat]) -> Doc
prRuleC _ (fun, _) | isNilFun fun || isOneFun fun = empty
prRuleC cat (fun, _) | isConsFun fun = vcat'
    [ "/********************   " <> c <> "    ********************/"
    , c <+> "make_" <> c <> parens (text m <+> "p1" <> "," <+> c <+> "p2")
    , lbrace
    , nest 4 $ vcat'
        [ c <+> "tmp = (" <> c <> ") malloc(sizeof(*tmp));"
        , "if (!tmp)"
        , lbrace
        , nest 4 $ vcat'
            [ "fprintf(stderr, \"Error: out of memory when allocating " <> c <> "!\\n\");"
            , "exit(1);" ]
        , rbrace
        , text $ "tmp->" ++ m' ++ " = " ++ "p1;"
        , "tmp->" <> v <+> "=" <+> "p2;"
        , "return tmp;" ]
    , rbrace ]
  where
    icat = identCat (normCat cat)
    c = text icat
    v = text (map toLower icat ++ "_")
    ListCat c' = cat            -- We're making a list constructor, so we
                                -- expect a list category
    m = identCat (normCat c')
    m' = map toLower m ++ "_"
prRuleC c (fun, cats) = vcat'
    [ text $ "/********************   " ++ fun ++ "    ********************/"
    , prConstructorC c fun vs cats ]
  where
    vs = getVars cats

-- | The constructor just assigns the parameters to the corresponding instance
-- variables.
-- >>> prConstructorC (Cat "A") "funa" [("A",1),("B",2)] [Cat "O", Cat "E"]
-- A make_funa(O p1, E p2)
-- {
--     A tmp = (A) malloc(sizeof(*tmp));
--     if (!tmp)
--     {
--         fprintf(stderr, "Error: out of memory when allocating funa!\n");
--         exit(1);
--     }
--     tmp->kind = is_funa;
--     tmp->u.funa_.a_ = p1;
--     tmp->u.funa_.b_2 = p2;
--     return tmp;
-- }
prConstructorC :: Cat -> String -> [IVar] -> [Cat] -> Doc
prConstructorC cat c vs cats = vcat'
    [ text (cat' ++ " make_" ++ c) <> parens args
    , lbrace
    , nest 4 $ vcat'
        [ text $ cat' ++ " tmp = (" ++ cat' ++ ") malloc(sizeof(*tmp));"
        , text "if (!tmp)"
        , lbrace
        , nest 4 $ vcat'
            [ text ("fprintf(stderr, \"Error: out of memory when allocating " ++ c ++ "!\\n\");")
            , text "exit(1);" ]
        , rbrace
        , text $ "tmp->kind = is_" ++ c ++ ";"
        , prAssigns c vs params
        , text "return tmp;" ]
    , rbrace ]
  where
    cat' = identCat (normCat cat)
    (types, params) = unzip (prParams cats)
    args = hsep $ punctuate comma $ zipWith (<+>) types params

-- | Prints the constructor's parameters. Returns pairs of type * name
-- >>> prParams [Cat "O", Cat "E"]
-- [(O,p1),(E,p2)]
prParams :: [Cat] -> [(Doc, Doc)]
prParams = zipWith prParam [1..]
  where
    prParam n c = (text (identCat c), text ("p" ++ show n))

-- | Prints the assignments of parameters to instance variables.
-- >>> prAssigns "A" [("A",1),("B",2)] [text "abc", text "def"]
-- tmp->u.a_.a_ = abc;
-- tmp->u.a_.b_2 = def;
prAssigns :: String -> [IVar] -> [Doc] -> Doc
prAssigns c vars params = vcat $ zipWith prAssign vars params
  where
    prAssign (t,n) p =
        text ("tmp->u." ++ c' ++ "_." ++ vname t n) <+> char '=' <+> p <> semi
    vname t n | n == 1 =
        case findIndices ((== t).fst) vars of
            [_] -> varName t
            _   -> varName t ++ showNum n
    vname t n = varName t ++ showNum n
    c' = map toLower c

{- **** Helper Functions **** -}

memName s = map toLower s ++ "_"
