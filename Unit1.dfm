object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Outil de dessin et cotation'
  ClientHeight = 424
  ClientWidth = 632
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poDesktopCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  OnResize = FormResize
  TextHeight = 15
  object PaintBox: TPaintBox
    Left = 0
    Top = 0
    Width = 632
    Height = 424
    Align = alClient
    OnMouseDown = PaintBoxMouseDown
    OnMouseMove = PaintBoxMouseMove
    OnMouseUp = PaintBoxMouseUp
    OnPaint = PaintBoxPaint
    ExplicitLeft = 128
    ExplicitTop = 96
    ExplicitWidth = 105
    ExplicitHeight = 105
  end
end
