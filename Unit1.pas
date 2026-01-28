unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, System.Types,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls;

type
  TForm1 = class(TForm)
    PaintBox: TPaintBox;
    // initialisation du formulaire
    procedure FormCreate(Sender: TObject);
    // libération des ressources
    procedure FormDestroy(Sender: TObject);
    // début du dessin / sélection
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    // aperçu en temps réel pendant le drag
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    // fin du dessin : ajout du segment
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    // rafraîchissement du PaintBox
    procedure PaintBoxPaint(Sender: TObject);
    // gestion clavier (Delete)
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    // redimensionnement du formulaire
    procedure FormResize(Sender: TObject);
  private
    { Déclarations privées }
    FIsDrawing: Boolean;
    // true si l'utilisateur est en train de tracer un segment
    FLastPoint: TPoint; // dernier point validé (utilisé pour l'aperçu)
    FFirstPoint: TPoint; // point de départ du segment en cours

  const
    GridSpacing = 20; // espacement de la grille en pixels
    // Convertit un point libre en point "aimanté" à la grille
    function SnapToGrid(const P: TPoint): TPoint;
    // Retourne True si P1->P2 est une diagonale 45° (|dx| = |dy|)
    function IsDiagonal(const P1, P2: TPoint): Boolean;
  end;

var
  Form1: TForm1;

implementation

uses
  Drawing; // unité qui gère le rendu, les segments et les cotations

{$R *.dfm}

var
  FDrawing: TDrawing; // instance partagée de la classe de dessin

  { SnapToGrid }
function TForm1.SnapToGrid(const P: TPoint): TPoint;
begin
  // Ramène les coordonnées au pas de grille défini par GridSpacing
  Result.X := Round(P.X / GridSpacing) * GridSpacing;
  Result.Y := Round(P.Y / GridSpacing) * GridSpacing;
end;

{ IsDiagonal }
function TForm1.IsDiagonal(const P1, P2: TPoint): Boolean;
var
  dx, dy: Integer;
begin
  // Vérifie si la différence en X et Y est identique en valeur absolue
  dx := P2.X - P1.X;
  dy := P2.Y - P1.Y;
  Result := Abs(dx) = Abs(dy);
end;

{ FormCreate }
procedure TForm1.FormCreate(Sender: TObject);
begin
  DoubleBuffered := True;
  KeyPreview := True;

  // Crée l'objet de dessin en lui passant le PaintBox cible
  FDrawing := TDrawing.Create(PaintBox);

  // Force la création des bitmaps internes à la taille actuelle du PaintBox
  // et dessine la grille / fond initial
  FDrawing.Resize;
  FDrawing.RedrawAll;
  PaintBox.Invalidate;

  // État initial : pas de dessin en cours
  FIsDrawing := False;
end;

{ FormDestroy }
procedure TForm1.FormDestroy(Sender: TObject);
begin
  // Libère l'instance de dessin
  FDrawing.Free;
end;

{ FormResize }
procedure TForm1.FormResize(Sender: TObject);
begin
  // Quand la fenêtre change de taille, adapter les bitmaps internes et redessiner
  if Assigned(FDrawing) then
  begin
    FDrawing.Resize;
    PaintBox.Invalidate;
  end;
end;

{ PaintBoxMouseDown }
procedure TForm1.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  selIdx: Integer;
begin
  // Laisser TDrawing gérer la sélection par clic (sélection d'un segment)
  if Assigned(FDrawing) then
    FDrawing.HandleMouseDown(Button, Shift, X, Y);

  // Si clic gauche et aucun segment sélectionné, démarrer un nouveau tracé
  if Button = mbLeft then
  begin
    selIdx := FDrawing.GetSelectedIndex;
    if selIdx >= 0 then
    begin
      // Un segment est sélectionné : on n'entame pas un nouveau dessin
      Exit;
    end;

    // Activer le mode dessin et mémoriser le point de départ (aimanté à la grille)
    FIsDrawing := True;
    P := SnapToGrid(Point(X, Y));
    FFirstPoint := P;
    FLastPoint := P;
  end;
end;

{ PaintBoxMouseMove }
procedure TForm1.PaintBoxMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  NewPoint: TPoint;
begin
  if not FIsDrawing then
    Exit;

  NewPoint := SnapToGrid(Point(X, Y));

  // Restaurer l'affichage de base (background + segments persistants)
  if Assigned(FDrawing) then
    FDrawing.RedrawAll;

  // Afficher un aperçu du segment et de sa cotation uniquement si la contrainte
  // (horizontal / vertical / diagonale 45°) est respectée
  if (NewPoint.X = FLastPoint.X) or (NewPoint.Y = FLastPoint.Y) or
    IsDiagonal(FLastPoint, NewPoint) then
  begin
    if Assigned(FDrawing) then
    begin
      // Dessin temporaire du segment (gris/rouge selon choix) — non persistant
      FDrawing.DrawLine(FFirstPoint, NewPoint, clRed, 1.5);
      // Dessin temporaire de la cotation (aperçu) le long du segment
      FDrawing.DrawDimension(FFirstPoint, NewPoint, clBlack, 1.5, 20, '', 12);
      // Copier le bitmap temporaire vers le PaintBox pour affichage immédiat
      FDrawing.UpdateImage;
    end;
  end
  else
  begin
    // Si la contrainte n'est pas respectée, on restaure simplement l'affichage de base
    if Assigned(FDrawing) then
      FDrawing.UpdateImage;
  end;

  // Mémoriser la dernière position pour la prochaine itération
  FLastPoint := NewPoint;
end;

{ PaintBoxMouseUp }
procedure TForm1.PaintBoxMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  EndPoint: TPoint;
begin
  if Button <> mbLeft then
    Exit;
  if not FIsDrawing then
    Exit;

  // Point final "aimanté" à la grille
  EndPoint := SnapToGrid(Point(X, Y));

  // Vérifier la contrainte (horiz/vert/diagonale) par rapport au point de départ
  if (EndPoint.X = FFirstPoint.X) or (EndPoint.Y = FFirstPoint.Y) or
    IsDiagonal(FFirstPoint, EndPoint) then
  begin
    if Assigned(FDrawing) then
    begin
      // Ajouter le segment de façon persistante et activer sa cotation
      FDrawing.AddSegment(FFirstPoint, EndPoint, clBlack, 2, True, '', 20, 12);
      // AddSegment appelle RedrawAll
      FDrawing.UpdateImage;
    end;
  end;

  // Fin du mode dessin et forcer le rafraîchissement du PaintBox
  FIsDrawing := False;
  PaintBox.Invalidate;
end;

{ PaintBoxPaint }
procedure TForm1.PaintBoxPaint(Sender: TObject);
begin
  // Lors du repaint du PaintBox, copier le bitmap GDI+ vers le Canvas
  if Assigned(FDrawing) then
    FDrawing.UpdateImage;
end;

{ FormKeyDown }
procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  // Déléguer la gestion des touches (ex : Delete) à l'objet de dessin
  if Assigned(FDrawing) then
    FDrawing.HandleKeyDown(Key, Shift);
end;

end.
