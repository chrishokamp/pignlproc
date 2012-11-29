/*
 * Wikipedia Statistics for Named Entity Recognition and Disambiguation
 *      - use Pig/hadoop to generate an inverted index
 * @params $OUTPUT_DIR - the directory where the files should be stored
 *         $STOPLIST_PATH - the location of the stoplist in HDFS                
 *         $STOPLIST_NAME - the filename of the stoplist
 *         $INPUT - the wikipedia XML dump
 *         $MIN_COUNT - the minumum count for a token to be included in the index
 *         $PIGNLPROC_JAR - the location of the pignlproc jar
 *         $LANG - the language of the Wikidump 
 *         $MAX_SPAN_LENGTH - the maximum length for a paragraph span
 *         $NUM_DOCS - the number of documents in this wikipedia dump
 *         $N - the number of tokens to keep
 *         - use the file 'indexer.pig.params' to supply a default configuration
 */

-- TEST: set parallelism level for reducers
SET default_parallel 7;

SET job.name 'Wikipedia-Tfidf-Inverted-Index for $LANG';
SET mapred.compress.map.output 'true';
SET mapred.map.output.compression.codec 'org.apache.hadoop.io.compress.GzipCodec';
-- Register the project jar to use the custom loaders and UDFs
REGISTER $PIGNLPROC_JAR;

-- Define aliases
DEFINE getTokens pignlproc.index.LuceneTokenizer('$STOPLIST_PATH', '$STOPLIST_NAME', '$LANG', '$ANALYZER_NAME');
--uncomment above and comment below to use default stoplist for the analyzer
--DEFINE getTokens pignlproc.index.LuceneTokenizer('$LANG', '$ANALYZER_NAME');
DEFINE textWithLink pignlproc.evaluation.ParagraphsWithLink('$MAX_SPAN_LENGTH');
--DEFINE JsonCompressedStorage pignlproc.storage.JsonCompressedStorage();

-- Parse the wikipedia dump and extract text and links data
parsed = LOAD '$INPUT'
  USING pignlproc.storage.ParsingWikipediaLoader('$LANG')
  AS (title, id, pageUrl, text, redirect, links, headers, paragraphs);


-- filter as early as possible
SPLIT parsed INTO
  parsedRedirects IF redirect IS NOT NULL,
  parsedNonRedirects IF redirect IS NULL;

-- Project articles
articles = FOREACH parsedNonRedirects GENERATE
  pageUrl,
  text,
  links,
  paragraphs;

--BEGIN store num articles
-- the next relation is created in order to get the global doc count
--grouped = GROUP articles ALL;

--numArticles = FOREACH grouped GENERATE
--	 COUNT(articles) AS total;

--STORE numArticles INTO '$OUTPUT_DIR/$LANG.numArticles.tsv' USING PigStorage('\t', '-schema');
--END store num articles


-- Extract paragraph contexts of the links 
paragraphs = FOREACH articles GENERATE
  pageUrl,
  FLATTEN(textWithLink(text, links, paragraphs))
  AS (paragraphIdx, paragraph, targetUri, startPos, endPos);
-----------------
-- BEGIN TFIDF --
-----------------
doc_context = FOREACH paragraphs GENERATE
        REGEX_EXTRACT(targetUri, '(.*)/(.*)', 2) AS uri,
        getTokens(paragraph) AS context;

all_contexts = GROUP doc_context by uri;

--added relation here to filter by number of contexts
size_filter = FILTER all_contexts BY
                COUNT(doc_context) >= $MIN_CONTEXTS;

flattened_context = FOREACH size_filter {
        contexts = doc_context.context;
        GENERATE
        group AS uri,
        FLATTEN(contexts) AS context;
};

raw_uri_and_token = FOREACH flattened_context GENERATE
        uri,
        FLATTEN(context) AS token: chararray;

uri_and_token = FILTER raw_uri_and_token BY SIZE(token) <= 25;

-- (2) group by token and Unique Doc to get global doc frequency
unique = DISTINCT uri_and_token;
--DUMP unique;
docs_by_tokens = GROUP unique by token;
--DUMP docs_by_tokens;
raw_doc_freq = FOREACH docs_by_tokens GENERATE
        group AS token,
	COUNT(unique) as df;

doc_freq = FILTER raw_doc_freq BY df > $MIN_COUNT;

raw_idf = FOREACH doc_freq GENERATE
        token,
        LOG((double)$NUM_DOCS/(double)df) AS idf: double;


idf = FILTER raw_idf BY (idf > 0);

--DUMP idf;
--ordered = order doc_freq BY df desc;
--STORE idf into '$OUTPUT_DIR/doc-frequency.json.bz2' USING JsonCompressedStorage;

--(3) Term Frequency
term_freq = GROUP uri_and_token by (uri, token);
term_counts = FOREACH term_freq GENERATE
        group.uri as uri,
        group.token as token,
        COUNT(uri_and_token) as tf;

--term_counts = FILTER raw_term_counts BY tf > $MIN_COUNT;

--(4) put the data together
token_instances = JOIN term_counts BY token, idf by token;

--(5) calculate tfidf
raw_tfidf = FOREACH token_instances {
        tf_idf = (double)term_counts::tf*(double)idf::idf;       
        GENERATE
                        term_counts::uri as uri,
                        term_counts::token as token,
                        tf_idf as weight;
};
tfidf = FILTER raw_tfidf BY (weight >= 1);

by_tokens = group tfidf BY token;
docs_with_weights = FOREACH by_tokens GENERATE
        group as token,
        tfidf.(uri,weight) as uris;

ordered = FOREACH docs_with_weights {
        sorted = ORDER uris by weight desc;
        GENERATE
        token, sorted;
};

--top = FOREACH ordered GENERATE
--        uri,
--        keepTopN(sorted) AS sorted;

--STORE ordered INTO '$OUTPUT_DIR/tfidf_inverted_index.json.bz2' USING JsonCompressedStorage();i
STORE ordered INTO '$OUTPUT_DIR/$LANG.tfidf_inverted_index.tsv.bz2' USING PigStorage('\t','-schema');

