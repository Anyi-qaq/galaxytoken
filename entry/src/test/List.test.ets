import adapterParsersTest from './AdapterParsers.test';
import breakpointsTest from './Breakpoints.test';
import customSourceTest from './CustomSource.test';
import jsonValueTest from './JsonValue.test';
import signerAndFormatTest from './SignerFormat.test';

export default function testsuite() {
  jsonValueTest();
  adapterParsersTest();
  signerAndFormatTest();
  customSourceTest();
  breakpointsTest();
}
