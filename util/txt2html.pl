#!/usr/bin/perl
$ARGV[0] or die "usage : txt2html [-t template] <txtfile> [out.html]\n\n"
	."\t -t\ttemplate file: default: a builtin xhtml header/footer.\n"
	."\t\tspecify 'none' for no header/footer\n";

%options;	# toc title RP
$options{tagline}='Conscious Computing';

while ( $ARGV[0] =~ /^-./ )
{
	$ARGV[0] eq '-t' and do {
		shift @ARGV;
		if ( $ARGV[0] eq 'none' )
		{
			$template = '${CONTENT}';
			shift @ARGV;
		}
		else
		{
			open IN, $_ = shift @ARGV or die "can't open template $_: $!";
			$template = join("", (<IN>) );
			close IN;
		}
	} or $ARGV[0] eq '--toc' and do {
		$options{toc} = 1;
		shift @ARGV;
	} or $ARGV[0] eq '--title' and do {
		shift @ARGV;
		$options{title} = shift @ARGV;
	} or $ARGV[0] eq '--rawtitle' and do {
		shift @ARGV;
		my $title = shift @ARGV;

		$title =~ s@^.*?/@@g;	# strip root of path
		$title =~ s/\.(txt|html)$//;	# strip suffix
		$title =~ s/([[:lower:]])([[:upper:]])/\1 \2/g;
		$options{title}=$title;
	} or $ARGV[0] eq '-p' and do {
		shift @ARGV;
		$options{RP} = shift @ARGV;
	} or $ARGV[0] eq '--onload' and do {
		shift @ARGV;
		$options{onload} = shift @ARGV;
	} or $ARGV[0] eq '--tagline' and do {
		shift @ARGV;
		$options{tagline} = shift @ARGV;
	} or die "unknown option: $ARGV[0]";

}

open IN, $ARGV[0] or die "can't open $ARG[0]: $!";
@l = <IN>;
close IN;

$c = "\n".join "", @l;

$c=~ s@&@&amp;@g;
$c=~ s@<@&lt;@g;

$c=~ s@\n+([^\n]+)\n=+\n@\n\n<h1>$1</h1>\n\n@g;
$c=~ s@\n+([^\n]+)\n-+\n@\n\n<h2>$1</h2>\n\n@g;
$c=~ s@\n+(=+([^\n=]+)=+)\n@\n\n<h1>$2</h1>\n\n@g;
$c=~ s@\n+(-+([^\n-]+)-+)\n@\n\n<h2>$2</h2>\n\n@g;
#$c=~ s@\n(\*\s+([^\n]+))\n@\n<h3>$2</h3>\n\n@g;

$c=~ s@(\n\t+[^\n]*)\n+(?=\n\t)@$1\n\t@g;
$c=~ s@\n(\*\s+([^\n]+)\n+((\t[^\n]*\n)+))+@\n<dt>$2</dt>\n<dd>\n$3</dd>\n\n@g;

$c=~ s@''([^']+)''@<code>$1</code>@g;

$c=~ s@((\n\t[^\n]*)+\n)@<pre>$1</pre>\n@g;
$c=~ s@((\n>[^\n]+)+\n)@<pre>$1</pre>\n@g;

$c=~ s@<pre>(.*?)</pre>\n+@'<PRE>'.&esc($1)."</PRE>\n"@ges;


sub esc { $_ = shift @_; s/\n/\r/g; return $_; }

# NOTES: pattern:  /(?=X)/:
#	lookahead:	(?=pat) (?!pat)
#	lookbehind:	(?<=,   (?<!

$TOK="<!---->";

# level 2
# a)
#$c=~ s@\n ([a-z])+\) ([^\n]+)@\n$TOK<li>$2</li>@g;
#$c=~ s@\n(($TOK<li>[^\n]+</li>\n)+)@\n<ol type="a">$1</ol>\n@g;
#$c=~ s@$TOK@@g;
$c=~ s@\n ([a-z])+\) ([^\n]+(\n\t[^\n]*)*)@\n<li>$2</li>@g;
$c=~ s@</li>\n<li>@</li><li>@g;
$c=~ s@\n((<li>[^\n]+</li>\n)+)@\n<ol type="a">$1</ol>\n@g;
# level 1
#a)
#$c=~ s@\n([a-z])+\) ([^\n]+(\n<ol.*?</ol>)*)@\n$TOK<li>$2</li>@g;
#$c=~ s@(?<!ol>)\n(($TOK<li>[^\n]+</li>\n)+)@\n<ol type="a">$1</ol>\n@g;
#$c=~ s@$TOK@ @g;
#$c=~ s@\n([a-z])+\) ([^\n]+(\n<ol.*?</ol>)*)@\n<li>$2</li>@g;
$c=~ s@\n([a-z])+\) ([^\n]+(\n<[^\n]+>|\n\t[^\n]*)*)@\n<li>$2</li>@g;
$c=~ s@</li>\n<li>@</li><li>@g;
$c=~ s@\n(<li>[^\n]+</li>)\n+@<ol type="a">$1</ol>\n@g;
#1) foo
#$c=~ s@\n([\d])+\) ([^\n]+\n<([^ >]+)[^>]+>.*?</\3>)@\n$TOK<li>$2</li>@g;
$c=~ s@\n([\d])+\) ([^\n]+(\n<[^\n]+>|\n\t[^\n]*)*)@"\n<li>".&esc($2)."</li>"@ges;
$c=~ s@li>\n<@li><@g;
$c=~ s@\n((<li>[^\n]+</li>)+)@\n<ol type="1">$1</ol>\n@g;

# level 3:
#    * foo
$c=~ s@\n    \* ([^\n]+)@\n<li>$1</li>@g;
$c=~ s@</li>\n<li>@</li><li>@g;
$c=~ s@\n(<li>[^\n]+</li>)\n@ <ul>$1</ul>\n@g;

# level 2
#  *foo
$c=~ s@\n  \* ([^\n]+)@\n<li>$1</li>@g;
$c=~ s@</li>\n<li>@</li><li>@g;
$c=~ s@\n(<li>[^\n]+</li>)\n@ <ul>$1</ul>\n@g;

# level 1
#*foo
$c=~ s@\n\* ([^\n]+)@\n<li>$1</li>@g;
$c=~ s@\n((<li>[^\n]+</li>\n)+)@\n<ul>\n$1</ul>\n@g;

# [label|site]
$c=~ s@(?<!\t)\[([^\|\]]+)\|([^\]]+)\]@<a href="$2">$1</a>@g;

# [#label] : anchor ref (same as [label|#label])
$c=~ s@(?<!\t)\[#([^\]]+)\]@<a href="#$1">$1</a>@g;
# [=label] : anchor definition
$c=~ s@(?<!\t)\[=([^\]]+)\]@<a name="$1"></a>@g;
#


#$c=~ s@\n\n+@\n</p>\n<p>\n@g;
#$c=~ s@\n([^\n]+\n)+<@\n<p>$1</p>\n<@g;


$c=~ s@\n([^<\n]{1,60})\n([^<\n]{70,}\n)@\n$1<br/>\n$2@g;


###########
# generate a TOC:
my $tmp = $c;
my $o="";
my $id=0;
my @toc;
while ( $tmp =~ /<h(.)>(.*?)<\/h\1>/ )
{
	push @toc, {link=>"<a href='#toc$id'>$2</a>", level=>$1};
	$tmp = $';
#	$_ = $&; s/<h(.)>/<h\1 id='toc$id'>/; $o.=$_;
	$o.=$` . "<a name='toc$id'\/>" . $&;
	$id++;
}

$c = $o . $tmp;

my $lev=0;
my $toc = "<h2>TOC</h2>\n";
foreach ( @toc ) {
	while ( $_->{level} < $lev )
	{
		$lev --;
		$toc .= "</ol>";
	}
	while ( $_->{level} > $lev )
	{
		$lev ++;
		$toc .= "<ol>";
	}

	$toc .= "<li>$_->{link}</li>\n";
}
while ( $lev-- > 0 )
{
	$toc .= "</ol>";
}


$c=~ tr/\r/\n/;
done:

@l=	grep {length($_) }
	split (/\n\n+/, $c);
$c = join( "\n", (map { /(<([^>\n]+)>.*?<\/\2>)/ ? "$_\n" : "<p>$_</p>\n" } @l) );

if ( $template )
{
	 $template =~ s/\$\{ONLOAD\}/$options{onload}/g;
	 $template =~ s/\$\{CONTENT\}/$c/g;
	 $template =~ s/\$\{TITLE\}/$options{title}/g;
	 $template =~ s/\$\{TOC\}/$toc/g;
	 $template =~ s/\$\{TAGLINE\}/$options{tagline}/g;
	 $template =~ s/\$\{RP\}/$options{RP}/g;
	 $c = $template;
}
else {
$c=<<"EOF";
<?xml version="1.0"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <title>$title</title>
  </head>
  <body>
<h1>$title</h1>
$toc
$c
  </body>
</html>
EOF
}

$ARGV[1] and do {
#-f $ARGV[1] and die "$ARGV[1] exists.";
open OUT, ">", $ARGV[1] or die;
print OUT $toc if $options{toc};
print OUT $c;
close OUT;
}
or do {
print $toc if $options{toc};
print $c;
};


exit;

done2:
	$c=~ tr/\r/\n/;
	goto done;
done3:
	$c=~ tr/\r/!/;
	goto done;
