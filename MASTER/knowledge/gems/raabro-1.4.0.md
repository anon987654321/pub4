require 'raabro'

module Fun include Raabro
  def pstart(i); rex(nil, i, /\(\s*/); end
  def pend(i);  rex(nil, i, /\)\s*/); end   # parentheses, optional trailing space
  def comma(i); rex(nil, i, /,\s*/); end
  def num(i);   rex(:num, i, /-?[0-9]+\s*/); end
  def args(i);  eseq(:args, i, :pstart, :exp, :comma, :pend); end
  def funname(i); rex(nil, i, /[a-z][a-z0-9]*/); end  def fun(i);   seq(:fun, i, :funname, :args); end
  def exp(i);   alt(:exp, i, :fun, :num); end
  # expression is a function or a number

  # rewrite rules
  def rewrite_exp(t); rewrite(t.children[0]); end  def rewrite_num(t); t.string.to_i; end
  def rewrite_fun(t)
    funame, *args = t.children    [funame.string] + args.map { |e| rewrite(e) }
  endend
