unit Drawing;

interface

uses
  Winapi.Windows,
  System.Classes,
  System.SysUtils,
  System.Math,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Vcl.Controls,
  Winapi.GDIPOBJ,
  Winapi.GDIPAPI,
  System.Types,
  System.Generics.Collections;

type
  {
    TSegment
    --------
    Représente un segment dessiné : points de début/fin, style (couleur, largeur),
    état de sélection et informations de cotation associées.
    Implémenté comme classe pour permettre la modification directe des champs
    stockés dans une TObjectList<TSegment>.
  }

  TSegment = class
  public
    StartPoint: TPoint;
    EndPoint: TPoint;
    Color: TColor;
    Width: Single;
    Selected: Boolean;
    HasDimension: Boolean;
    DimensionText: string;
    DimensionOffset: Integer;
    DimensionFontSize: Single;
    constructor Create(const AStart, AEnd: TPoint; AColor: TColor;
      AWidth: Single);
  end;

  TDrawing = class
  private
    FPaintBox: TPaintBox; // contrôle cible pour l'affichage
    FBitmap: TGPBitmap; // bitmap composite visible
    FGraphics: TGPGraphics; // graphics associé à FBitmap
    FBackgroundBmp: TGPBitmap; // bitmap de fond (fond + grille)
    FBackgroundGraphics: TGPGraphics; // graphics associé au background
    FSegments: TObjectList<TSegment>; // liste des segments (owned)
    FSelectedIndex: Integer; // index du segment sélectionné (-1 si aucun)
    FGridSpacing: Integer; // espacement de la grille (px)
    FGridColor: TColor; // couleur de la grille
    FBackgroundValid: Boolean; // indique si le background est à jour

    function TColorToGDIPlusColor(AColor: TColor): TGPColor;
    procedure DrawSegments;
    // dessine toutes les cotations (méthode utilitaire)
    function PointToSegmentDistance(const P: TPoint;
      const AStart, AEnd: TPoint): Single;
    // construit le background si nécessaire
    procedure EnsureBackground;
    // vrai si au moins un segment est sélectionné
    function AnySelected: Boolean;

  public
    constructor Create(APaintBox: TPaintBox; AGridSpacing: Integer = 20;
      AGridColor: TColor = clSilver);
    destructor Destroy; override;

    // Propriétés de grille (lecture/écriture simples)
    property GridSpacing: Integer read FGridSpacing write FGridSpacing;
    property GridColor: TColor read FGridColor write FGridColor;

    // Opérations de dessin de base
    procedure Clear(AColor: TColor);
    procedure DrawLine(const AStart, AEnd: TPoint; AColor: TColor;
      AWidth: Single);
    procedure DrawGrid(Spacing: Integer; AColor: TColor; AWidth: Single = 1);

    // Cotation (dessin immédiat sur le bitmap courant)
    procedure DrawDimension(const AStart, AEnd: TPoint; AColor: TColor;
      AWidth: Single; Offset: Integer = 20; const Text: string = '';
      FontSize: Single = 10);

    // Rendu / redimensionnement
    procedure UpdateImage;
    procedure Resize;

    // Gestion des segments
    function AddSegment(const AStart, AEnd: TPoint; AColor: TColor;
      AWidth: Single; AHasDimension: Boolean = False;
      const ADimensionText: string = ''; AOffset: Integer = 20;
      AFontSize: Single = 10): Integer;
    procedure ClearSegments;
    function SelectSegmentAt(const P: TPoint; Tolerance: Integer = 6): Integer;
    procedure DeselectAll;
    function GetSelectedIndex: Integer;
    procedure HandleMouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);

    // Gestion clavier / suppression
    procedure HandleKeyDown(var Key: Word; Shift: TShiftState);
    procedure DeleteSelectedSegment;

    // Redessine tout (background + segments + cotations) et met à jour l'affichage
    procedure RedrawAll;
  end;

implementation

{ TSegment }

constructor TSegment.Create(const AStart, AEnd: TPoint; AColor: TColor;
  AWidth: Single);
begin
  inherited Create;
  StartPoint := AStart;
  EndPoint := AEnd;
  Color := AColor;
  Width := AWidth;
  Selected := False;
  HasDimension := False;
  DimensionText := '';
  DimensionOffset := 20;
  DimensionFontSize := 10;
end;

{ TDrawing }

constructor TDrawing.Create(APaintBox: TPaintBox; AGridSpacing: Integer = 20;
  AGridColor: TColor = clSilver);
var
  bmpWidth, bmpHeight: Integer;
begin
  inherited Create;
  // Référence au PaintBox cible
  FPaintBox := APaintBox;
  FGridSpacing := AGridSpacing;
  FGridColor := AGridColor;

  // Créer les bitmaps à la taille actuelle du PaintBox (au moins 1x1)
  bmpWidth := Max(1, FPaintBox.Width);
  bmpHeight := Max(1, FPaintBox.Height);

  // Bitmap visible (composite)
  FBitmap := TGPBitmap.Create(bmpWidth, bmpHeight, PixelFormat32bppARGB);
  FGraphics := TGPGraphics.Create(FBitmap);
  FGraphics.SetSmoothingMode(SmoothingModeHighQuality);

  // Bitmap de fond (grid + fond) pour optimisation
  FBackgroundBmp := TGPBitmap.Create(bmpWidth, bmpHeight, PixelFormat32bppARGB);
  FBackgroundGraphics := TGPGraphics.Create(FBackgroundBmp);
  FBackgroundGraphics.SetSmoothingMode(SmoothingModeHighQuality);
  FBackgroundValid := False;

  // Liste de segments (owned = True => la liste libère les objets)
  FSegments := TObjectList<TSegment>.Create(True);
  FSelectedIndex := -1;
end;

destructor TDrawing.Destroy;
begin
  // Libération des ressources GDI+ et de la liste
  FSegments.Free;
  if Assigned(FBackgroundGraphics) then
    FreeAndNil(FBackgroundGraphics);
  if Assigned(FBackgroundBmp) then
    FreeAndNil(FBackgroundBmp);
  if Assigned(FGraphics) then
    FreeAndNil(FGraphics);
  if Assigned(FBitmap) then
    FreeAndNil(FBitmap);
  inherited Destroy;
end;

function TDrawing.TColorToGDIPlusColor(AColor: TColor): TGPColor;
var
  R, G, B: Byte;
begin
  // Convertit un TColor VCL en TGPColor (alpha = 255)
  AColor := ColorToRGB(AColor);
  R := GetRValue(AColor);
  G := GetGValue(AColor);
  B := GetBValue(AColor);
  Result := MakeColor(255, R, G, B);
end;

procedure TDrawing.Clear(AColor: TColor);
begin
  // Efface le bitmap visible avec la couleur donnée
  if Assigned(FGraphics) then
    FGraphics.Clear(TColorToGDIPlusColor(AColor));
  // Invalide le background si on change le fond
  FBackgroundValid := False;
end;

procedure TDrawing.DrawLine(const AStart, AEnd: TPoint; AColor: TColor;
  AWidth: Single);
var
  Pen: TGPPen;
begin
  // Dessine une ligne simple sur le bitmap courant (utilisé pour aperçu temporaire)
  if not Assigned(FGraphics) then
    Exit;
  Pen := TGPPen.Create(TColorToGDIPlusColor(AColor), AWidth);
  try
    Pen.SetLineJoin(LineJoinRound);
    FGraphics.DrawLine(Pen, AStart.X, AStart.Y, AEnd.X, AEnd.Y);
  finally
    Pen.Free;
  end;
end;

procedure TDrawing.DrawGrid(Spacing: Integer; AColor: TColor;
  AWidth: Single = 1);
var
  Pen: TGPPen;
  X, Y: Integer;
  w, h: Integer;
begin
  // Dessine la grille sur le bitmap de background (optimisation)
  if not Assigned(FBackgroundGraphics) then
    Exit;
  Pen := TGPPen.Create(TColorToGDIPlusColor(AColor), AWidth);
  try
    w := FBackgroundBmp.GetWidth;
    h := FBackgroundBmp.GetHeight;
    X := 0;
    while X <= w do
    begin
      FBackgroundGraphics.DrawLine(Pen, X, 0, X, h);
      Inc(X, Spacing);
    end;
    Y := 0;
    while Y <= h do
    begin
      FBackgroundGraphics.DrawLine(Pen, 0, Y, w, Y);
      Inc(Y, Spacing);
    end;
  finally
    Pen.Free;
  end;
end;

procedure TDrawing.EnsureBackground;
begin
  // Construit le background (fond blanc + grille) si nécessaire.
  // Appelé avant chaque RedrawAll pour garantir que le background est prêt.
  if not Assigned(FBackgroundGraphics) then
    Exit;
  if FBackgroundValid then
    Exit;

  // Fond blanc opaque
  FBackgroundGraphics.Clear(MakeColor(255, 255, 255, 255));
  // Dessin de la grille sur le background
  DrawGrid(FGridSpacing, FGridColor, 1);
  FBackgroundValid := True;
end;

function TDrawing.AnySelected: Boolean;
var
  i: Integer;
begin
  // Retourne True si au moins un segment est sélectionné
  for i := 0 to FSegments.Count - 1 do
    if FSegments[i].Selected then
      Exit(True);
  Result := False;
end;

procedure TDrawing.DrawSegments;
var
  i: Integer;
  seg: TSegment;
  Pen: TGPPen;
  penColor, accentColor: TGPColor;
  accentWidth: Single;
  brush: TGPSolidBrush;
  drawDimensionsNow: Boolean;
begin
  // Dessine tous les segments sur le bitmap courant (FGraphics).
  // Si au moins un segment est sélectionné, on masque toutes les cotations
  if not Assigned(FGraphics) then
    Exit;

  drawDimensionsNow := not AnySelected;

  for i := 0 to FSegments.Count - 1 do
  begin
    seg := FSegments[i];
    penColor := TColorToGDIPlusColor(seg.Color);

    if seg.Selected then
    begin
      // Style visuel pour la sélection : trait d'accent plus large + segment normal par dessus
      accentColor := MakeColor(255, 0, 120, 215);
      accentWidth := Max(1.0, seg.Width + 2.0);

      Pen := TGPPen.Create(accentColor, accentWidth);
      try
        Pen.SetLineJoin(LineJoinRound);
        FGraphics.DrawLine(Pen, seg.StartPoint.X, seg.StartPoint.Y,
          seg.EndPoint.X, seg.EndPoint.Y);
      finally
        Pen.Free;
      end;

      // Dessiner le segment réel par dessus pour conserver sa couleur d'origine
      Pen := TGPPen.Create(penColor, seg.Width);
      try
        Pen.SetLineJoin(LineJoinRound);
        FGraphics.DrawLine(Pen, seg.StartPoint.X, seg.StartPoint.Y,
          seg.EndPoint.X, seg.EndPoint.Y);
      finally
        Pen.Free;
      end;

      // Marqueurs aux extrémités
      brush := TGPSolidBrush.Create(MakeColor(255, 255, 255, 255));
      try
        FGraphics.FillEllipse(brush, seg.StartPoint.X - 4,
          seg.StartPoint.Y - 4, 8, 8);
        FGraphics.FillEllipse(brush, seg.EndPoint.X - 4,
          seg.EndPoint.Y - 4, 8, 8);
      finally
        brush.Free;
      end;

      Pen := TGPPen.Create(MakeColor(255, 0, 0, 0), 1);
      try
        FGraphics.DrawEllipse(Pen, seg.StartPoint.X - 4,
          seg.StartPoint.Y - 4, 8, 8);
        FGraphics.DrawEllipse(Pen, seg.EndPoint.X - 4,
          seg.EndPoint.Y - 4, 8, 8);
      finally
        Pen.Free;
      end;
    end
    else
    begin
      // Segment non sélectionné
      Pen := TGPPen.Create(penColor, seg.Width);
      try
        Pen.SetLineJoin(LineJoinRound);
        FGraphics.DrawLine(Pen, seg.StartPoint.X, seg.StartPoint.Y,
          seg.EndPoint.X, seg.EndPoint.Y);
      finally
        Pen.Free;
      end;
    end;

    // Dessiner la cotation si elle existe et si l'on doit afficher les cotations
    if seg.HasDimension and drawDimensionsNow then
      DrawDimension(seg.StartPoint, seg.EndPoint, clRed, 1.5,
        seg.DimensionOffset, seg.DimensionText, seg.DimensionFontSize);
  end;
end;

procedure TDrawing.DrawDimension(const AStart, AEnd: TPoint; AColor: TColor;
  AWidth: Single; Offset: Integer = 20; const Text: string = '';
  FontSize: Single = 10);
var
  Pen: TGPPen;
  dx, dy, len, ux, uy: Single;
  nx, ny: Single;
  sx1, sy1, sx2, sy2: Single;
  midX, midY: Single;
  displayText: string;
  gFont: TGPFont;
  gBrush, bgBrush: TGPSolidBrush;
  fmt: TGPStringFormat;
  state: ULONG;
  angleRad, angleDeg: Single;
  layoutRect, measuredRect: TGPRectF;
  padding, textGap, tickSize: Single;
  penColor, brushColor: TGPColor;
  gpPt: TGPPointF;
  availableLen: Single;
  needLeader: Boolean;
  leaderOffset: Single;
  leaderEndX, leaderEndY: Single;
  UnitScale: Single;
  UnitName: string;
begin
  // Dessine une cotation (dimension) pour le segment AStart-AEnd sur FGraphics.
  if not Assigned(FGraphics) then
    Exit;

  UnitScale := 1.0;
  UnitName := 'px';

  penColor := TColorToGDIPlusColor(AColor);
  brushColor := TColorToGDIPlusColor(AColor);

  dx := AEnd.X - AStart.X;
  dy := AEnd.Y - AStart.Y;
  len := Sqrt(dx * dx + dy * dy);
  if len <= 0 then
    Exit;

  // vecteur unitaire le long du segment (u) et vecteur normal (n)
  ux := dx / len;
  uy := dy / len;
  nx := -uy;
  ny := ux;

  // positions des lignes de cote (décalées de Offset)
  sx1 := AStart.X + nx * Offset;
  sy1 := AStart.Y + ny * Offset;
  sx2 := AEnd.X + nx * Offset;
  sy2 := AEnd.Y + ny * Offset;

  midX := (sx1 + sx2) / 2;
  midY := (sy1 + sy2) / 2;

  if Text = '' then
    displayText := FormatFloat('0.##', len * UnitScale) + ' ' + UnitName
  else
    displayText := Text;

  tickSize := Max(4.0, FontSize * 0.6);
  padding := Max(3.0, FontSize * 0.25);
  textGap := Max(4.0, FontSize * 0.5);

  Pen := TGPPen.Create(penColor, AWidth);
  try
    Pen.SetLineJoin(LineJoinRound);

    // Dessin des lignes de cote et des "ticks" aux extrémités
    FGraphics.DrawLine(Pen, AStart.X, AStart.Y, sx1, sy1);
    FGraphics.DrawLine(Pen, AEnd.X, AEnd.Y, sx2, sy2);
    FGraphics.DrawLine(Pen, sx1, sy1, sx2, sy2);

    FGraphics.DrawLine(Pen, AStart.X + nx * tickSize * 0.5,
      AStart.Y + ny * tickSize * 0.5, AStart.X - nx * tickSize * 0.5,
      AStart.Y - ny * tickSize * 0.5);
    FGraphics.DrawLine(Pen, AEnd.X + nx * tickSize * 0.5,
      AEnd.Y + ny * tickSize * 0.5, AEnd.X - nx * tickSize * 0.5,
      AEnd.Y - ny * tickSize * 0.5);

    gFont := TGPFont.Create('Tahoma', FontSize, FontStyleRegular, UnitPixel);
    try
      gBrush := TGPSolidBrush.Create(brushColor);
      try
        fmt := TGPStringFormat.Create;
        try
          fmt.SetAlignment(StringAlignmentCenter);
          fmt.SetLineAlignment(StringAlignmentCenter);

          // Mesure du texte pour décider si on place le texte centré ou en leader
          layoutRect.X := 0.0;
          layoutRect.Y := 0.0;
          layoutRect.Width := Abs(sx2 - sx1) + 200.0;
          layoutRect.Height := FontSize * 4.0;

          measuredRect.X := 0.0;
          measuredRect.Y := 0.0;
          measuredRect.Width := 0.0;
          measuredRect.Height := 0.0;

          FGraphics.MeasureString(displayText, -1, gFont, layoutRect, fmt,
            measuredRect);
          availableLen := Sqrt((sx2 - sx1) * (sx2 - sx1) + (sy2 - sy1) *
            (sy2 - sy1));
          needLeader := measuredRect.Width + 2 * padding + textGap >
            availableLen;

          angleRad := ArcTan2(uy, ux);
          angleDeg := angleRad * 180.0 / Pi;

          // Normaliser l'angle pour éviter texte à l'envers
          if angleDeg > 90.0 then
            angleDeg := angleDeg - 180.0
          else if angleDeg < -90.0 then
            angleDeg := angleDeg + 180.0;

          state := FGraphics.Save;
          try
            if not needLeader then
            begin
              // Texte centré le long de la cote
              FGraphics.TranslateTransform(midX, midY);
              FGraphics.RotateTransform(angleDeg);

              layoutRect.Width := measuredRect.Width + 2 * padding;
              layoutRect.Height := measuredRect.Height + 2 * padding;
              layoutRect.X := -layoutRect.Width / 2;
              layoutRect.Y := -layoutRect.Height / 2;

              bgBrush := TGPSolidBrush.Create(MakeColor(200, 255, 255, 255));
              try
                FGraphics.FillRectangle(bgBrush, layoutRect.X, layoutRect.Y,
                  layoutRect.Width, layoutRect.Height);
              finally
                bgBrush.Free;
              end;

              gpPt.X := 0.0;
              gpPt.Y := 0.0;
              FGraphics.DrawString(displayText, -1, gFont, gpPt, fmt, gBrush);
            end
            else
            begin
              // Texte en leader (décalé) si l'espace est insuffisant
              leaderOffset := Offset + tickSize + textGap + measuredRect.Height
                / 2 + padding;
              leaderEndX := midX + nx * leaderOffset;
              leaderEndY := midY + ny * leaderOffset;

              FGraphics.TranslateTransform(leaderEndX, leaderEndY);
              if Abs(angleDeg) < 30 then
                FGraphics.RotateTransform(0)
              else
                FGraphics.RotateTransform(angleDeg);

              layoutRect.Width := measuredRect.Width + 2 * padding;
              layoutRect.Height := measuredRect.Height + 2 * padding;
              layoutRect.X := -layoutRect.Width / 2;
              layoutRect.Y := -layoutRect.Height / 2;

              bgBrush := TGPSolidBrush.Create(MakeColor(200, 255, 255, 255));
              try
                FGraphics.FillRectangle(bgBrush, layoutRect.X, layoutRect.Y,
                  layoutRect.Width, layoutRect.Height);
              finally
                bgBrush.Free;
              end;

              gpPt.X := 0.0;
              gpPt.Y := 0.0;
              FGraphics.DrawString(displayText, -1, gFont, gpPt, fmt, gBrush);

              // Restaurer la transformation et dessiner la ligne leader
              FGraphics.Restore(state);
              state := FGraphics.Save;
              try
                FGraphics.DrawLine(Pen, midX, midY, leaderEndX, leaderEndY);
              finally
              end;
            end;
          finally
            FGraphics.Restore(state);
          end;

        finally
          fmt.Free;
        end;
      finally
        gBrush.Free;
      end;
    finally
      gFont.Free;
    end;

  finally
    Pen.Free;
  end;
end;

procedure TDrawing.UpdateImage;
var
  hBm: HBITMAP;
  MemDC: HDC;
  OldBmp: HBITMAP;
  DestDC: HDC;
  w, h: Integer;
  status: TStatus;
begin
  // Copie le bitmap GDI+ (FBitmap) vers le Canvas du PaintBox via un HBITMAP temporaire.
  if not Assigned(FBitmap) or not Assigned(FPaintBox) then
    Exit;

  w := FBitmap.GetWidth;
  h := FBitmap.GetHeight;

  status := FBitmap.GetHBITMAP(MakeColor(255, 255, 255, 255), hBm);
  if status <> Ok then
    Exit;

  try
    DestDC := FPaintBox.Canvas.Handle;
    MemDC := CreateCompatibleDC(DestDC);
    if MemDC = 0 then
      Exit;
    OldBmp := SelectObject(MemDC, hBm);

    try
      BitBlt(DestDC, 0, 0, w, h, MemDC, 0, 0, SRCCOPY);
    finally
      SelectObject(MemDC, OldBmp);
      DeleteDC(MemDC);
    end;
  finally
    DeleteObject(hBm);
  end;
end;

procedure TDrawing.Resize;
var
  NewWidth, NewHeight: Integer;
begin
  // Recrée les bitmaps à la nouvelle taille du PaintBox.
  if not Assigned(FPaintBox) then
    Exit;
  NewWidth := Max(1, FPaintBox.Width);
  NewHeight := Max(1, FPaintBox.Height);

  // Libération sécurisée des anciens objets
  if Assigned(FGraphics) then
    FreeAndNil(FGraphics);
  if Assigned(FBitmap) then
    FreeAndNil(FBitmap);
  if Assigned(FBackgroundGraphics) then
    FreeAndNil(FBackgroundGraphics);
  if Assigned(FBackgroundBmp) then
    FreeAndNil(FBackgroundBmp);

  // Recréation des bitmaps et graphics
  FBitmap := TGPBitmap.Create(NewWidth, NewHeight, PixelFormat32bppARGB);
  FGraphics := TGPGraphics.Create(FBitmap);
  FGraphics.SetSmoothingMode(SmoothingModeHighQuality);

  FBackgroundBmp := TGPBitmap.Create(NewWidth, NewHeight, PixelFormat32bppARGB);
  FBackgroundGraphics := TGPGraphics.Create(FBackgroundBmp);
  FBackgroundGraphics.SetSmoothingMode(SmoothingModeHighQuality);

  // Le background doit être reconstruit
  FBackgroundValid := False;

  // Redessiner tout pour mettre à jour l'affichage
  RedrawAll;
end;

function TDrawing.AddSegment(const AStart, AEnd: TPoint; AColor: TColor;
  AWidth: Single; AHasDimension: Boolean = False;
  const ADimensionText: string = ''; AOffset: Integer = 20;
  AFontSize: Single = 10): Integer;
var
  seg: TSegment;
begin
  // Crée un nouveau segment
  seg := TSegment.Create(AStart, AEnd, AColor, AWidth);
  seg.HasDimension := AHasDimension;
  seg.DimensionText := ADimensionText;
  seg.DimensionOffset := AOffset;
  seg.DimensionFontSize := AFontSize;
  Result := FSegments.Add(seg);

  // Redessiner tout (RedrawAll gère background + segments)
  RedrawAll;
end;

procedure TDrawing.ClearSegments;
begin
  // Supprime tous les segments et réinitialise la sélection
  FSegments.Clear;
  FSelectedIndex := -1;
  RedrawAll;
end;

function TDrawing.PointToSegmentDistance(const P: TPoint;
  const AStart, AEnd: TPoint): Single;
var
  vx, vy, wx, wy: Single;
  c1, c2, B: Single;
  projx, projy: Single;
begin
  // Calcule la distance minimale entre le point P et le segment [AStart,AEnd]
  vx := AEnd.X - AStart.X;
  vy := AEnd.Y - AStart.Y;
  wx := P.X - AStart.X;
  wy := P.Y - AStart.Y;

  if (Abs(vx) < 1E-6) and (Abs(vy) < 1E-6) then
  begin
    // Segment de longueur nulle : distance au point AStart
    Result := Sqrt(Sqr(P.X - AStart.X) + Sqr(P.Y - AStart.Y));
    Exit;
  end;

  c1 := vx * wx + vy * wy;
  c2 := vx * vx + vy * vy;
  B := c1 / c2;

  if B <= 0 then
  begin
    projx := AStart.X;
    projy := AStart.Y;
  end
  else if B >= 1 then
  begin
    projx := AEnd.X;
    projy := AEnd.Y;
  end
  else
  begin
    projx := AStart.X + B * vx;
    projy := AStart.Y + B * vy;
  end;

  Result := Sqrt(Sqr(P.X - projx) + Sqr(P.Y - projy));
end;

function TDrawing.SelectSegmentAt(const P: TPoint;
  Tolerance: Integer = 6): Integer;
var
  i: Integer;
  d, bestD: Single;
  bestIdx: Integer;
  tol: Single;
begin
  // Sélectionne le segment le plus proche du point P si la distance est <= tol.
  Result := -1;
  if FSegments.Count = 0 then
    Exit;

  bestIdx := -1;
  bestD := 1E9;
  tol := Tolerance;

  for i := 0 to FSegments.Count - 1 do
  begin
    d := PointToSegmentDistance(P, FSegments[i].StartPoint,
      FSegments[i].EndPoint);
    if d < bestD then
    begin
      bestD := d;
      bestIdx := i;
    end;
  end;

  if (bestIdx >= 0) and (bestD <= tol) then
  begin
    // Sélectionner l'élément trouvé : désélectionner les autres, marquer l'index
    DeselectAll;
    FSegments[bestIdx].Selected := True;
    FSelectedIndex := bestIdx;
    Result := bestIdx;
    RedrawAll;
  end
  else
  begin
    // Aucune sélection : désélectionner tout et redessiner
    DeselectAll;
    RedrawAll;
  end;
end;

procedure TDrawing.DeselectAll;
var
  i: Integer;
begin
  // Désélectionne tous les segments
  for i := 0 to FSegments.Count - 1 do
    FSegments[i].Selected := False;
  FSelectedIndex := -1;
end;

function TDrawing.GetSelectedIndex: Integer;
begin
  Result := FSelectedIndex;
end;

procedure TDrawing.HandleMouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  // Méthode utilitaire à appeler depuis le OnMouseDown du PaintBox
  if Button = mbLeft then
    SelectSegmentAt(Point(X, Y), 6);
end;

procedure TDrawing.HandleKeyDown(var Key: Word; Shift: TShiftState);
begin
  // Gestion clavier : Delete supprime le segment sélectionné
  if Key = VK_DELETE then
  begin
    DeleteSelectedSegment;
    Key := 0;
  end;
end;

procedure TDrawing.DeleteSelectedSegment;
begin
  // Supprime le segment actuellement sélectionné (si existant) et redessine
  if (FSelectedIndex >= 0) and (FSelectedIndex < FSegments.Count) then
  begin
    FSegments.Delete(FSelectedIndex);
    FSelectedIndex := -1;
    RedrawAll;
  end;
end;

procedure TDrawing.RedrawAll;
begin
  // Redessine l'ensemble : copie le background (fond+grille) puis dessine les segments/cotations
  if not Assigned(FGraphics) or not Assigned(FBackgroundGraphics) then
    Exit;

  EnsureBackground;
  // Copier le background dans le bitmap visible
  FGraphics.Clear(MakeColor(0, 0, 0, 0));
  FGraphics.DrawImage(FBackgroundBmp, 0, 0);

  // Dessiner les segments et cotations par-dessus
  DrawSegments;
  // Mettre à jour le PaintBox
  UpdateImage;
end;

end.
