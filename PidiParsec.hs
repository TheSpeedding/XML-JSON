-- Library author: https://github.com/exaexa
-- Slightly modified: Ignoring whitespaces, parsing booleans, parsing null values, parsing whitespaces.

module PidiParsec where

  import Control.Applicative
  import Control.Monad.State.Strict

  data Parser a = Parser (State String (Maybe a))

  -- monad instance from the bottom up
  instance Functor Parser where
    fmap f (Parser s) = Parser $ fmap (fmap f) s
  instance Applicative Parser where
    pure a = Parser . pure . pure $ a
    Parser l <*> Parser r = Parser (liftA2 (<*>) l r) 
  instance Monad Parser where
    return = pure
    Parser l >>= p = Parser $ do 
                                  a <- l
                                  case a of
                                            Nothing -> return Nothing
                                            Just a -> let Parser r = p a in r
  instance Alternative Parser where
    empty = Parser $ pure empty -- empty is Nothing in this case
    Parser l <|> Parser r = Parser $ do s0 <- get
                                        ll <- l  -- try to get the result of l
                                        case ll of
                                          Nothing -> put s0 >> r -- if it failed, restore original state and run r
                                          a -> return a  -- otherwise return whatever it returned

  parseFail = empty -- fail hard
  parseGet = Parser $ Just <$> get -- get the rest of the parsed string
  parseSet s = Parser $ Just <$> put s -- set the rest of parsed string

  -- parse out the EOF (a.k.a. verify we're on the end of the string)
  pEof = do s <- parseGet
            case s of
              "" -> return () -- looks okay
              _ -> parseFail -- certainly not on the end

  -- runners
  doParse (Parser p) = runState p
  doParseEof p = fst . doParse (p >>= \r -> pEof >> return r)

  -- parse out any character (and return it monadically)
  pAny = do s <- parseGet
            case s of
              (i:ss) -> parseSet ss >> return i
              _ -> parseFail

  pCharCond f = pAny >>= \c -> if f c then return c
                                      else parseFail
                                      
  -- parse out a character from a limited range of characters
  pOneOf cs = pCharCond (`elem` cs)
  pAnyExcept cs = pCharCond $ not.(`elem` cs)
  pChar c = pCharCond (== c)

  -- parse out an exact string
  pStr s = mapM pChar s

  -- parse out a boolean
  pBool = do
            s <- parseGet
            case s of 
              ('t':'r':'u':'e':ss)     -> parseSet ss >> return True
              ('f':'a':'l':'s':'e':ss) -> parseSet ss >> return False
              _ -> parseFail

  -- parse out a null value
  pNull = do
            s <- parseGet
            case s of
              ('n':'u':'l':'l':ss) -> parseSet ss >> return ()
              _ -> parseFail

  -- parse out one given thing at least once (and return the results concatenated to a list)
  pMany1 :: Parser a -> Parser [a]
  pMany1 p = do x <- p
                xs <- pMany p
                return (x:xs)

  -- kleene star
  pMany :: Parser a -> Parser [a]
  pMany p = pMany1 p <|> pure []


  pWhiteSpace = pMany (pOneOf " \n\t\r")

  -- parse out something bracketed from left and right, ignoring whitespaces
  pBracketedIgnore l r p = do pWhiteSpace
                              l
                              pWhiteSpace
                              res <- p
                              pWhiteSpace
                              r
                              pWhiteSpace
                              return res

  -- parse out something bracketed from left and right
  pBracketed l r p = do l
                        res <- p
                        r
                        return res

  pDelim l r = pBracketed (pStr l) (pStr r)
  pBrackets = pDelim "[" "]"
  pBraces = pDelim "{" "}"

  pDelimIgnore l r = pBracketedIgnore (pStr l) (pStr r)
  pBracketsIgnore = pDelimIgnore "[" "]"
  pBracesIgnore = pDelimIgnore "{" "}"

  pQuoted q = pDelim q q . pMany $ pAnyExcept q

  -- an useful tool: Just 1 <:> Just [2,3] == Just (1:[2,3]) == Just [1,2,3]
  infixr 4 <:>
  a <:> b = (:) <$> a <*> b

  -- a more useful tool: many1 with separator
  -- pSep (pChar ',') (pStr "asd") parses "asd,asd,asd,..."
  pSep1 s p = p <:> (pWhiteSpace >> s >> pWhiteSpace >> pSep1 s p)
              <|>
              (:[]) <$> p

  -- maw function (:[]) is the same as (\x -> [x]).
  -- (Also same as 'pure' in this context, but let's avoid too much polymorphism here.)

  pSep s p = pSep1 s p <|> return []

  pCommaDelimited = pSep (pChar ',')

  pWSDelimited = pSep pWhiteSpace

  pToken t = pWhiteSpace >> t