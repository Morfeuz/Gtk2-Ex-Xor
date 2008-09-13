# Copyright 2007, 2008 Kevin Ryde

# This file is part of Gtk2-Ex-Xor.
#
# Gtk2-Ex-Xor is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 2, or (at your option) any
# later version.
#
# Gtk2-Ex-Xor is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Xor.  If not, see <http://www.gnu.org/licenses/>.

package Gtk2::Ex::Xor;
use strict;
use warnings;
use Carp;
use Gtk2;

# set this to 1 for some diagnostic prints
use constant DEBUG => 0;

our $VERSION = 2;


sub get_gc {
  my ($widget, $fg_color, @params) = @_;

  my $xor_bg_color = $widget->Gtk2_Ex_Xor_background;
  my $colormap = $widget->get_colormap;

  if (! defined $fg_color) {
  STYLE:
    $fg_color = $widget->get_style->fg ($widget->state);

  } else {
    if (ref $fg_color) {
      $fg_color = $fg_color->copy;
    } else {
      my $str = $fg_color;
      $fg_color = Gtk2::Gdk::Color->parse ($str);
      if (! $fg_color) {
        carp "Gtk2::Gdk::Color->parse() cannot parse '$str' (fallback on style foreground)";
        goto STYLE;
      }
    }
    $colormap->rgb_find_color ($fg_color);
  }

  if (DEBUG) { printf "    pixels fg %#x bg %#x xor %#x\n",
                 $fg_color->pixel, $xor_bg_color->pixel,
                   $fg_color->pixel ^ $xor_bg_color->pixel ; }
  my $xor_color = Gtk2::Gdk::Color->new
    (0,0,0, $fg_color->pixel ^ $xor_bg_color->pixel);

  my $window = $widget->Gtk2_Ex_Xor_window;
  my $depth = $window->get_depth;
  return Gtk2::GC->get ($depth, $colormap,
                        { function   => 'xor',
                          foreground => $xor_color,
                          background => $xor_color,
                          @params
                        });
}

sub _event_widget_coords {
  my ($widget, $event) = @_;
  my $x = $event->x;
  my $y = $event->y;
  my $eventwin = $event->window;
  if ($eventwin != $widget->window) {
    my ($wx, $wy) = $eventwin->get_position;
    if (DEBUG) { print "  subwindow offset $wx,$wy\n"; }
    $x += $wx;
    $y += $wy;
  }
  return ($x, $y);
}


#------------------------------------------------------------------------------
# background colour hacks

# default is from the widget's Gtk2::Style, but with an undocumented
# 'Gtk2_Ex_Xor_background' as an override
#
sub Gtk2::Widget::Gtk2_Ex_Xor_background {
  my ($widget) = @_;
  if (exists $widget->{'Gtk2_Ex_Xor_background'}) {
    return $widget->{'Gtk2_Ex_Xor_background'};
  }
  return $widget->Gtk2_Ex_Xor_background_from_style;
}

# "bg" is the background for normal widgets
sub Gtk2::Widget::Gtk2_Ex_Xor_background_from_style {
  my ($widget) = @_;
  return $widget->get_style->bg ($widget->state);
}

# "base" is the background for text-oriented widgets like Gtk2::Entry and
# Gtk2::TextView.  TextView has multiple windows, so this is the colour
# meant for the main text window.
#
sub Gtk2::Entry::Gtk2_Ex_Xor_background_from_style {
  my ($widget) = @_;
  return $widget->get_style->base ($widget->state);
}
*Gtk2::TextView::Gtk2_Ex_Xor_background_from_style
  = \&Gtk2::Entry::Gtk2_Ex_Xor_background_from_style;

# For Gtk2::Bin subclasses such as Gtk2::EventBox, look at the child's
# background if there's a child and if it's a no-window widget, since that
# child is what will be xored over.
#
# Perhaps this should be only some of the Bin classes, like Gtk2::Window,
# EventBox and Alignment.
#
package Gtk2::Bin;
use strict;
use warnings;
sub Gtk2_Ex_Xor_background {
  my ($widget) = @_;
  # same override as above ...
  if (exists $widget->{'Gtk2_Ex_Xor_background'}) {
    return $widget->{'Gtk2_Ex_Xor_background'};
  }
  if (my $child = $widget->get_child) {
    if ($child->flags & 'no-window') {
      return $child->Gtk2_Ex_Xor_background;
    }
  }
  return $widget->SUPER::Gtk2_Ex_Xor_background;
}
package Gtk2::Ex::Xor;


#------------------------------------------------------------------------------
# window choice hacks

# normal "->window" for most widgets
*Gtk2::Widget::Gtk2_Ex_Xor_window = \&Gtk2::Widget::window;

# for Gtk2::Layout must draw into its "bin_window"
*Gtk2::Layout::Gtk2_Ex_Xor_window = \&Gtk2::Layout::bin_window;

sub Gtk2::TextView::Gtk2_Ex_Xor_window {
  my ($textview) = @_;
  return $textview->get_window ('text');
}

# GtkEntry has a window and then within that a subwindow just 4 pixels
# smaller in height.  The latter is what it draws on.
#
# The following code as per Gtk2::Ex::WidgetCursor.  Since the subwindow
# isn't a documented feature check that it does, in fact, exist.
#
# The alternative would be "include inferiors" on the xor gc's.  But that'd
# probably cause problems on windowed widget children, since expose events
# in them wouldn't be seen by the parent's expose to redraw the
# crosshair/lasso/etc.
#
sub Gtk2::Entry::Gtk2_Ex_Xor_window {
  my ($widget) = @_;
  my $win = $widget->window || return undef; # if unrealized
  return ($win->get_children)[0] # first child
    || $widget->SUPER::Gtk2_Ex_Xor_window;
}

# GooCanvas draws on a subwindow too, also undocumented it seems
# (there's a tmp_window too, but that's only an overlay suppressing some
# expose events or something at selected times)
*Goo::Canvas::Gtk2_Ex_Xor_window = \&Gtk2::Entry::Gtk2_Ex_Xor_window;

1;
__END__

# Not sure about this yet
#
#
# =head1 NAME
# 
# Gtk2::Ex::Xor -- shared support for widget add-ons drawing with XOR
# 
# =head1 SYNOPSIS
# 
#  use Gtk2::Ex::Xor;
#  my $colour = $widget->Gtk2_Ex_Xor_background;
# 
# =head1 FUNCTIONS
# 
# =over 4
# 
# =item C<< $widget->Gtk2_Ex_Xor_background() >>
# 
# Return a C<Gtk2::Gdk::Color> object, with an allocated pixel value, which is
# the background to XOR against in C<$widget>.
# 
# =back
# 
# =head1 SEE ALSO
# 
# L<Gtk2::Ex::CrossHair>, L<Gtk2::Ex::Lasso>