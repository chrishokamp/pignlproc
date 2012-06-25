package pignlproc.index;




import org.apache.lucene.analysis.Analyzer;

import org.apache.lucene.analysis.TokenStream;
import org.apache.lucene.analysis.standard.StandardAnalyzer;
import org.apache.lucene.analysis.tokenattributes.TermAttribute;
import org.apache.lucene.util.Version;

import org.apache.pig.EvalFunc;
import org.apache.pig.data.BagFactory;
import org.apache.pig.data.DataBag;
import org.apache.pig.data.DataType;
import org.apache.pig.data.Tuple;
import org.apache.pig.data.TupleFactory;
import org.apache.pig.impl.logicalLayer.schema.Schema;
import org.apache.pig.impl.logicalLayer.schema.Schema.FieldSchema;

import java.io.IOException;
import java.io.StringReader;


/**
 /**
 * @author chrishokamp
 * Take a bag of paragraphs (usage contexts) and emit a bag of tokens using the Lucene Standard analyzer
 *
 */
public class Lucene_Tokenizer extends EvalFunc<DataBag> {
    TupleFactory tupleFactory = TupleFactory.getInstance();
    BagFactory bagFactory = BagFactory.getInstance();
    //Hard-coded for the Lucene standard analyzer because this is unnecessary for this implementation
    String field = "paragraph";


    protected Analyzer analyzer = new StandardAnalyzer(Version.LUCENE_30);
    private TokenStream stream = null;

    public Lucene_Tokenizer() throws  IOException {
       stream = analyzer.reusableTokenStream(field, new StringReader(""));
    }

    @Override
    public DataBag exec(Tuple input) throws IOException {


            DataBag out = bagFactory.newDefaultBag();

            Object t0 = input.get(0);
            if (!(t0 instanceof String)) {
              throw new IOException(
                     "Expected a String, but this is a "
                             + t0.getClass().getName());
             }

            stream = analyzer.reusableTokenStream(field, new StringReader((String)t0));

            try {
                while (stream.incrementToken()) {
                    String token = stream.getAttribute(TermAttribute.class).term();
                    out.add(tupleFactory.newTuple(token));
                }
            }
            catch (IOException e) {
                   //shouldn't be thrown
            }
            return out;

    }

    public Schema outputSchema(Schema input) {
        try {
            Schema tupleSchema = new Schema();
            tupleSchema.add(new FieldSchema("token", DataType.CHARARRAY));
            return new Schema(new Schema.FieldSchema(getSchemaName(
                    this.getClass().getName().toLowerCase(), input),
                    tupleSchema, DataType.BAG));
        } catch (Exception e) {
            return null;
        }
    }

}






