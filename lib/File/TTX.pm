package File::TTX;

use warnings;
use strict;
use XML::xmlapi;
use POSIX qw/strftime/;

=head1 NAME

File::TTX - Utilities for dealing with TRADOS TTX files

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';


=head1 SYNOPSIS

TRADOS has been more or less the definitive set of translation tools for over a decade; more to the point, they're the
tools I use most.  There are two basic modes used by TRADOS to interact with documents.  The first is in Word documents, which
is not addressed in this module.  The second is with TagEditor, which has TTX files as its native file format.  TTX files are
a breed of XML, so they're actually pretty easy to work with.

    use File::TTX;

    my $foo = File::TTX->load('myfile.ttx');
    ... do stuff with it ...
    $foo->write();
    
Each TTX consists of a header and body text.  The header contains various information about the file you can read and write;
the text is, well, the text of the document.  Before translation, the text consists of just plain text, but as you work TagEditor
I<segments> the file into segments, each of which is translated in isolation.  (The paradigm here is that if you re-encounter a
segment or something similar to one you've already done, the translation memory will provide you with the translation, either
automatically writing it if it's identical, or at least presenting it to you to speed things up if it's just similar.)

A common mode is to read things with a script, build a TTX, and write it out for translation with TagEditor.  Here's the kind
of functions you'd use for that:

   use File::TTX;

   my $ttx = File::TTX->new();

   $ttx->append_text("This is a sentence.\n");
   $ttx->append_mark("test mark");
   $ttx->append_text("\n");
   $ttx->append_text("This is another sentence.\n");

   $ttx->write ("my.ttx");
   
After translation, you can use the marks to find out where you are in the file (they'll be skipped during translation without
being removed from the file).

There are two basic modes for content extraction; either you want to scan all content, or you're just interested in the segments
so you can toss them into an Excel spreadsheet or something.  These work pretty much the same; to scan all elements, you use
C<content_elements> as follows; it returns a list of C<File::TTX::Content> elements, documented below, which are really just 
C<XML::xmlapi> elements with a little extra sugar for convenience.

   use File::TTX;
   my $ttx = File::TTX->load('myfile.ttx');
   
   foreach my $piece ($ttx->content_elements) {
      if ($piece->type eq 'mark') {
         # something
      } elsif ($piece->type eq 'segment') {
         print $piece->translated . "\n";
      }
   }
   
To do a more data-oriented extraction, you'd want the C<segments> function, and the loop would look more like this:

   foreach my $s ($ttx->segments) {
      print $s->source . " - " . $s->translated . "\n";
   }
   
Clear?  Sure it is.

There are still plenty of gaps in this API; I plan to extend it as I run into new use cases.  Now that I've actually put the
darned thing on CPAN, I won't lose it in the meantime, so I won't have to rewrite it.  Again.  This is the fourth time, if
you're keeping count.  (And of course, since this is the first time I've managed to upload it, you I<can't> be keeping count.)

=head1 CREATING A TTX OBJECT

=head2 new()

The C<new> function creates a blank TTX so you can build whatever you want and write it out.  If you've already got an XML::xmlapi
structure (that's the library used internally for XML representation here) then you can pass it in and it will be broken down
into useful structural components for the element access functions.

=cut

sub new {
   my ($class, %input) = @_;
   my $self = bless {}, $class;
   if ($input{'xml'}) {
      $self->{xml} = $input{'xml'};
   } else {
      $self->{xml} = XML::xmlapi->parse ('<TRADOStag Version="2.0"><FrontMatter><ToolSettings/><UserSettings/></FrontMatter><Body><Raw></Raw></Body></TRADOStag>');
   }
   $self->{'frontmatter'} = $self->{xml}->search_first ('FrontMatter');
   $self->{'toolsettings'} = $self->{frontmatter}->search_first ('ToolSettings');
   $self->{'usersettings'} = $self->{frontmatter}->search_first ('UserSettings');
   $self->{'body'} = $self->{xml}->search_first ('Raw');
   
   my $lookup = sub {
      my ($field, $where, $default) = @_;
      return $input{$field} if $input{$field};
      return $self->{$where}->get ($field, $default);
   };
   
   $self->{toolsettings}->set ('CreationTool',        $lookup->('CreationTool',        'toolsettings', 'perl with File::TTX'));
   $self->{toolsettings}->set ('CreationDate',        $lookup->('CreationDate',        'toolsettings', $self->date_now));
   $self->{toolsettings}->set ('CreationToolVersion', $lookup->('CreationToolVersion', 'toolsettings', $VERSION));
   
   $self->{usersettings}->set ('SourceDocumentPath',  $lookup->('SourceDocumentPath',  'usersettings', ''));
   $self->{usersettings}->set ('O-Encoding',          $lookup->('O-Encoding',          'usersettings', 'windows-1252'));
   $self->{usersettings}->set ('TargetLanguage',      $lookup->('TargetLanguage',      'usersettings', 'EN-US'));
   $self->{usersettings}->set ('PlugInInfo',          $lookup->('PlugInInfo',          'usersettings', ''));
   $self->{usersettings}->set ('SourceLanguage',      $lookup->('SourceLanguage',      'usersettings', 'DE-DE'));
   $self->{usersettings}->set ('SettingsPath',        $lookup->('SettingsPath',        'usersettings', ''));
   $self->{usersettings}->set ('SettingsRelativePath',$lookup->('SettingsRelativePath','usersettings', ''));
   $self->{usersettings}->set ('DataType',            $lookup->('DataType',            'usersettings', 'RTF'));
   $self->{usersettings}->set ('SettingsName',        $lookup->('SettingsName',        'usersettings', ''));
   $self->{usersettings}->set ('TargetDefaultFont',   $lookup->('TargetDefaultFont',   'usersettings', ''));
   
   return $self;
}


=head2 load()

The C<load> function loads an existing TTX.  Said file will remember where it came from, so you don't have to give the
filename again when you write it (assuming you write it, of course).

=cut

sub load {
   my ($class, $file) = @_;
   my $xml = XML::xmlapi->parse_from_file($file);
   return $class->new(xml => $xml);
}

=head1 FILE MANIPULATION

=head2 write($file)

Writes a TTX out to disk; the C<$file> can be omitted if you used C<load> to make the object and you want the file to write
to the same place.

=cut

sub write {
   my ($self, $file) = @_;
   $file = $self->{file} unless $file;
   
   $self->{xml}->write_UCS2LE($file);
}

=head1 HEADER ACCESS

Here are a bunch of functions to access and/or modify different things in the header.  Pass any of them a value to set that
value.

=head2 CreationTool(), CreationDate(), CreationToolVersion()

These are in the ToolSettings part of the header.  Mostly you don't care about them.

=cut

sub CreationTool        { $_[0]->{toolsettings}->set_or_get ('CreationTool',        $_[1]) }
sub CreationDate        { $_[0]->{toolsettings}->set_or_get ('CreationDate',        $_[1]) }
sub CreationToolVersion { $_[0]->{toolsettings}->set_or_get ('CreationToolVersion', $_[1]) }

=head2 SourceDocumentPath(), OEncoding(), TargetLanguage(), PlugInInfo(), SourceLanguage(), SettingsPath(), SettingsRelativePath(), DataType(), SettingsName(), TargetDefaultFont()

These are in the UserSettings part of the header.  Frankly, mostly you don't care about these either, but here we're getting
into the reason for this module, like writing a quick script to read or change the source and target languages of TTX files.

=cut

sub SourceDocumentPath   { $_[0]->{usersettings}->set_or_get ('SourceDocumentPath',   $_[1]) }
sub OEncoding            { $_[0]->{usersettings}->set_or_get ('O-Encoding',           $_[1]) }
sub TargetLanguage       { $_[0]->{usersettings}->set_or_get ('TargetLanguage',       $_[1]) }
sub PlugInInfo           { $_[0]->{usersettings}->set_or_get ('PlugInInfo',           $_[1]) }
sub SourceLanguage       { $_[0]->{usersettings}->set_or_get ('SourceLanguage',       $_[1]) }
sub SettingsPath         { $_[0]->{usersettings}->set_or_get ('SettingsPath',         $_[1]) }
sub SettingsRelativePath { $_[0]->{usersettings}->set_or_get ('SettingsRelativePath', $_[1]) }
sub DataType             { $_[0]->{usersettings}->set_or_get ('DataType',             $_[1]) }
sub SettingsName         { $_[0]->{usersettings}->set_or_get ('SettingsName',         $_[1]) }
sub TargetDefaultFont    { $_[0]->{usersettings}->set_or_get ('TargetDefaultFont',    $_[1]) }

=head2 slang(), tlang()

These are quicker versions of SourceLanguage and TargetLanguage; they cache the values for repeated use (and they do get used
repeatedly).  The drawback is they're actually slower for files without a source or target language defined, but this actually
doesn't happen all that often.  At least I hope not.

=cut

sub slang {
   my ($self, $l) = @_;
   if (defined $l) {
      $self->{slang} = $self->SourceLanguage($l);
      return $self->{slang};
   }
   return $self->{slang} if $self->{slang};
   $self->{slang} = $self->SourceLanguage();
   $self->{slang};
}
sub tlang {
   my ($self, $l) = @_;
   if (defined $l) {
      $self->{tlang} = $self->TargetLanguage($l);
      return $self->{tlang};
   }
   return $self->{tlang} if $self->{tlang};
   $self->{tlang} = $self->TargetLanguage();
   $self->{tlang};
}

=head1 WRITING TO THE BODY

=head2 append_text($string)

Append a string to the end of the body.  It's the caller's responsibility to terminate the line.

=cut

sub append_text {
   my ($self, $str) = @_;
   $self->{body}->append (XML::xmlapi->createtext($str));
}

=head2 append_segment($source, $target, $match, $slang, $tlang, $origin)

Appends a segment to the body.  Only C<$source> and C<$target> are required; C<$match> defaults to 0, and defaults for C<$slang>
and C<$tlang> (the source and target languages) default to the master values in the header.  Note that TagEditor I<really> doesn't
like you to mix languages, but who am I to stand in your way in this matter?  Finally, C<$origin> defaults to unspecified.
TagEditor sets it to "manual"; probably "Align" is another value, but I haven't verified that.

If the header doesn't actually have a source or target language, and you specify one or the other here, it will be written to
the header as the default source or target language.

=cut

sub append_segment {
   my ($self, $source, $target, $match, $slang, $tlang, $origin) = @_;
   
   $match = 0 unless $match;
   
   if ($slang) {
      my $lang = $self->slang;
      $self->slang($slang) unless $lang;
   } else {
      $slang = $self->slang;
   }
   if ($tlang) {
      my $lang = $self->tlang;
      $self->tlang($tlang) unless $lang;
   } else {
      $tlang = $self->tlang;
   }
   
   $source = XML::xmlapi->escape ($source);
   $target = XML::xmlapi->escape ($target);
   my $tu = XML::xmlapi->parse ("<Tu MatchPercent=\"$match\"/>");
   $tu->set ('origin', $origin) if defined $origin;
   $tu->append (XML::xmlapi->parse ("<Tuv Lang=\"$slang\">$source</Tuv>"));
   $tu->append (XML::xmlapi->parse ("<Tuv Lang=\"$tlang\">$target</Tuv>"));
   
   $self->{body}->append ($tu);
}

=head2 append_mark($string, $tag)

Appends a non-opening, non-closing tag to the body.  (External style, e.g. text in Word that doesn't get translated.)
This is useful for setting marks for script coordination, which is why I call it append_mark.

The default appearance is "text", but you can add C<$tag> if you want something else.

=cut

sub append_mark {
   my ($self, $text, $tag) = @_;
   $tag = 'text' unless $tag;
   $text = XML::xmlapi->escape($text);
   my $mark = XML::xmlapi->parse ("<ut DisplayText=\"$tag\" Style=\"external\">$text</ut>");
   $self->{body}->append($mark);
}

=head2 append_open_tag($string, $tag), append_close_tag ($string, $tag)

Appends a opening or closing tag.  Here, the C<$tag> is required.  (Well, it will default to 'cf' if you screw up.  But don't.)

=cut

sub append_open_tag {
   my ($self, $text, $tag) = @_;
   $tag = 'cf' unless $tag;
   $text = XML::xmlapi_escape($text);
   my $mark = XML::xmlapi_parse ("<ut LeftEdge=\"angle\" Style=\"external\" DisplayText=\"$tag\" Type=\"start\">$text</ut>");
   $self->{body}->append($mark);
}
sub append_close_tag {
   my ($self, $text, $tag) = @_;
   $tag = '/cf' unless $tag;
   $text = XML::xmlapi_escape($text);
   my $mark = XML::xmlapi_parse ("<ut RightEdge=\"angle\" Style=\"external\" DisplayText=\"$tag\" Type=\"end\">$text</ut>");
   $self->{body}->append($mark);
}

=head1 READING FROM THE BODY

Since a TTX is structured data, not just text, reading from it consists of iterating across its child elements.  These elements
are L<XML::xmlapi> elements due to the underlying XML nature of the TTX file.  I suppose some convenience functions might be a
good idea, but frankly it's so easy to use the XML::xmlapi functions (well, I did write XML::xmlapi) that I haven't needed any
so far.  This might be a place to watch for further details.

=head2 content_elements()

Returns all the content elements in a list.  Text may be broken up into multiple chunks, depending on how it was added.

=cut
sub content_elements {
   my ($self) = @_;
   my @returns = $self->{body}->children;
   foreach (@returns) {
      File::TTX::Content->rebless($_);
   }
   @returns;
}

=head2 segments()

Returns a list of just the segments in the body.  Useful for data extraction.

=cut

sub segments {
   my $self = shift;
   my @returns = $self->{body}->search('Tu');
   foreach (@returns) {
      File::TTX::Content->rebless($_);
   }
   @returns;
}


=head1 MISCELLANEOUS STUFF

=head2 date_now()

Formats the current time the way TTX likes it.

=cut

sub date_now { strftime ('%Y%m%dT%H%M%SZ', localtime); }


=head1 File::TTX::Content

This helper class wraps the L<XML::xmlapi> parts returned by C<content_elements>, providing a little more comfort when working
with them.

=cut

package File::TTX::Content;

use base qw(XML::xmlapi);
use warnings;
use strict;

=head2 rebless($xml)

Called on an XML::xmlapi element to rebless it as a File::TTX::Content element.  This is a class method.

=cut

sub rebless {
   my ($class, $xml) = @_;
   bless $xml, $class;
}

=head2 type()

Returns the type of content piece.  The possible answers are 'text', 'open', 'close', 'segment', and 'mark'.

=cut

sub type {
   my $self = shift;
   
   return 'text' unless $self->is_element;
   return 'segment' if $self->is('Tu');
   if ($self->is('ut')) {
      return 'open'  if $self->get('Type') eq 'start';
      return 'close' if $self->get('Type') eq 'end';
      return 'mark';
   }
   return 'unknown';
}

=head2 tag()

Returns (or sets) the tag or mark text of a tag or mark.

=cut

sub tag {
   my $self = shift;
   my $type = $self->type;
   return '' if $type eq 'text';
   return '' if $type eq 'segment';
   return $self->set_or_get("DisplayText", shift);
}

=head2 translated()

Returns the translated content of a segment, or just the content for anything else.  Use with care.

=cut

sub translated {
   my $self = shift;
   my $type = $self->type;
   return $self->content unless $type eq 'segment';
   my @t = $self->elements();
   return $t[1]->content if defined $t[1];
   return $t[0]->content;
}

=head2 source()

Returns the source content of a segment, or just the content for anything else.

=cut

sub source {
   my $self = shift;
   my $type = $self->type;
   return $self->content unless $type eq 'segment';
   my $t = $self->search_first('Tuv');
   return $t->content;
}

=head2 match()

Returns and/or sets the recorded match percent of a segment (or 0 if it's not a segment).

=cut

sub match {
   my $self = shift;
   my $type = $self->type;
   return 0 unless $type eq 'segment';
   $self->set_or_get('MatchPercent', shift);
}

=head2 Other things we'll want

The XML::xmlapi doesn't support the full range of XML manipulation in its current incarnation, so I'll need to revisit it, and
also I don't need all this functionality today, but here's what the content handler should be able to do:

 - Segment non-segmented text, replacing a chunk or series of chunks (in case neighboring text chunks don't cover a full segment)
   with a segment or a segment-plus-extra-text.
 - Translate a segment, i.e. replace the translated content.
 - Modify the source of a segment (just in case).
 - See and set the source and target languages of a segment.
 
If you are actually using Perl to access TTX files and would like to do these things, then by all means drop me a line and tell me
to get the lead out.

=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-file-ttx at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=File-TTX>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc File::TTX


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=File-TTX>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/File-TTX>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/File-TTX>

=item * Search CPAN

L<http://search.cpan.org/dist/File-TTX/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of File::TTX
