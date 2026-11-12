// SnipTool.m v3 - floating "Rectangular Snip" button for injected iOS apps
// - Nút 38pt, kéo di chuyển được, chạm để chụp & crop vùng chọn
// - Sau khi chọn vùng: vẽ lên ảnh
//     bút tay (giữ yên ngón tay ~0.5s để tự sửa nét: đường thẳng / hình chữ nhật / vuông / tròn / elip / tam giác)
//     hình chữ nhật, hình elip/tròn, mũi tên (kéo để vẽ), nhập chữ
//     5 màu (màu vàng = bút dạ quang), 3 cỡ nét, undo
// - Chạm 3 ngón 2 lần: ẩn / hiện nút (trạng thái được lưu)
// - Kết quả: copy vào clipboard + mở share sheet (chọn "Save Image" để lưu vào Ảnh)

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kFX = @"SnipTool.fx";
static NSString *const kFY = @"SnipTool.fy";
static NSString *const kHidden = @"SnipTool.hidden";
static const void *kAttachedKey = &kAttachedKey;

static const CGFloat kBtnSize = 38;

static UIButton *STRoundButton(NSString *symbol, UIColor *bg, CGFloat size) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, size, size);
    b.backgroundColor = bg;
    b.layer.cornerRadius = size / 2;
    b.tintColor = UIColor.whiteColor;
    if (symbol) {
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.4 weight:UIImageSymbolWeightBold];
        UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:c];
        [b setImage:img forState:UIControlStateNormal];
    }
    return b;
}

#pragma mark - Passthrough window / root VC

@interface STWindow : UIWindow
@end
@implementation STWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (v == self || v == self.rootViewController.view) return nil; // cho touch xuyên xuống app
    return v;
}
@end

@interface STRootVC : UIViewController
@property (nonatomic, copy) void (^onLayout)(void);
@end
@implementation STRootVC
- (void)loadView {
    UIView *v = [UIView new];
    v.backgroundColor = UIColor.clearColor;
    self.view = v;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.onLayout) self.onLayout();
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

#pragma mark - Floating button (38pt, vùng chạm 44pt)

@interface STButton : UIView
@end
@implementation STButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, kBtnSize, kBtnSize)];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.layer.cornerRadius = kBtnSize / 2;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.7].CGColor;
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightBold];
    UIImage *img = [UIImage systemImageNamed:@"crop" withConfiguration:c]
                ?: [UIImage systemImageNamed:@"viewfinder" withConfiguration:c];
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.tintColor = UIColor.whiteColor;
    iv.frame = self.bounds;
    iv.contentMode = UIViewContentModeCenter;
    [self addSubview:iv];
    return self;
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    return CGRectContainsPoint(CGRectInset(self.bounds, -3, -3), p);
}
@end

#pragma mark - Selection overlay

@interface STSnipView : UIView
@property (nonatomic, copy) void (^onDone)(CGRect rect); // CGRectNull = hủy
- (instancetype)initWithImage:(UIImage *)image frame:(CGRect)frame;
@end

@implementation STSnipView {
    UIImageView *_iv;
    CAShapeLayer *_dim, *_border;
    CGRect _sel;
    UIButton *_ok, *_no, *_close;
    UILabel *_hint;
    CGSize _initialSize;
    BOOL _finished;
}

- (instancetype)initWithImage:(UIImage *)image frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _initialSize = frame.size;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _iv = [[UIImageView alloc] initWithImage:image];
    _iv.frame = self.bounds;
    _iv.autoresizingMask = self.autoresizingMask;
    [self addSubview:_iv];

    _dim = [CAShapeLayer layer];
    _dim.fillRule = kCAFillRuleEvenOdd;
    _dim.fillColor = [UIColor colorWithWhite:0 alpha:0.5].CGColor;
    [self.layer addSublayer:_dim];

    _border = [CAShapeLayer layer];
    _border.fillColor = nil;
    _border.strokeColor = UIColor.whiteColor.CGColor;
    _border.lineWidth = 1.5;
    _border.lineDashPattern = @[@6, @3];
    [self.layer addSublayer:_border];

    _hint = [UILabel new];
    _hint.text = @"Kéo để chọn vùng cần chụp";
    _hint.textColor = UIColor.whiteColor;
    _hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _hint.textAlignment = NSTextAlignmentCenter;
    _hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    _hint.layer.cornerRadius = 12;
    _hint.clipsToBounds = YES;
    [self addSubview:_hint];

    _close = STRoundButton(@"xmark", [UIColor colorWithWhite:0 alpha:0.6], 34);
    [_close addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_close];

    _ok = STRoundButton(@"checkmark", [UIColor colorWithRed:0.18 green:0.7 blue:0.35 alpha:0.95], 40);
    [_ok addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    _no = STRoundButton(@"xmark", [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:0.95], 40);
    [_no addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    _ok.hidden = _no.hidden = YES;
    [self addSubview:_ok];
    [self addSubview:_no];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];

    [self redraw];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(self.bounds.size, _initialSize) && !_finished) {
        // xoay màn hình -> ảnh đóng băng không còn khớp, hủy
        dispatch_async(dispatch_get_main_queue(), ^{ [self cancel]; });
        return;
    }
    UIEdgeInsets s = self.safeAreaInsets;
    _hint.frame = CGRectMake((self.bounds.size.width - 210) / 2, s.top + 12, 210, 28);
    _close.center = CGPointMake(self.bounds.size.width - s.right - 30, s.top + 26);
    _dim.frame = _border.frame = self.bounds;
}

- (void)redraw {
    UIBezierPath *p = [UIBezierPath bezierPathWithRect:self.bounds];
    BOOL has = !CGRectIsEmpty(_sel);
    if (has) [p appendPath:[UIBezierPath bezierPathWithRect:_sel]];
    _dim.path = p.CGPath;
    _border.path = has ? [UIBezierPath bezierPathWithRect:_sel].CGPath : nil;
}

- (void)placeButtons {
    CGFloat midX = CGRectGetMidX(_sel);
    CGFloat y = CGRectGetMaxY(_sel) + 10;
    UIEdgeInsets s = self.safeAreaInsets;
    if (y + 40 > self.bounds.size.height - s.bottom - 4) y = CGRectGetMaxY(_sel) - 50; // hết chỗ -> đặt trong vùng chọn
    y = MAX(y, s.top + 4);
    CGFloat minX = s.left + 44, maxX = self.bounds.size.width - s.right - 44;
    CGFloat cx = MIN(MAX(midX, minX), maxX);
    _no.center = CGPointMake(cx - 26, y + 20);
    _ok.center = CGPointMake(cx + 26, y + 20);
    _ok.hidden = _no.hidden = NO;
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint pt = [g locationInView:self];
    CGPoint t = [g translationInView:self];
    CGPoint start = CGPointMake(pt.x - t.x, pt.y - t.y);
    if (g.state == UIGestureRecognizerStateBegan) {
        _ok.hidden = _no.hidden = YES;
        _hint.hidden = YES;
    }
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        CGRect r = CGRectStandardize(CGRectMake(start.x, start.y, pt.x - start.x, pt.y - start.y));
        _sel = CGRectIntersection(r, self.bounds);
        [self redraw];
    } else if (g.state == UIGestureRecognizerStateEnded) {
        if (_sel.size.width < 20 || _sel.size.height < 20) {
            _sel = CGRectZero;
            _hint.hidden = NO;
            [self redraw];
        } else {
            [self placeButtons];
        }
    } else if (g.state == UIGestureRecognizerStateCancelled) {
        _sel = CGRectZero;
        _hint.hidden = NO;
        [self redraw];
    }
}

- (void)confirm {
    if (_finished || CGRectIsEmpty(_sel)) return;
    _finished = YES;
    if (self.onDone) self.onDone(_sel);
}
- (void)cancel {
    if (_finished) return;
    _finished = YES;
    if (self.onDone) self.onDone(CGRectNull);
}
@end

#pragma mark - Hình học / nhận dạng nét

static inline CGFloat STDist(CGPoint a, CGPoint b) { return hypot(a.x - b.x, a.y - b.y); }

static CGFloat STSegDist(CGPoint p, CGPoint a, CGPoint b) {
    CGFloat dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
    if (l2 < 1e-6) return STDist(p, a);
    CGFloat t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2;
    t = MIN(MAX(t, 0), 1);
    return STDist(p, CGPointMake(a.x + t * dx, a.y + t * dy));
}

static void STDP(const CGPoint *p, NSInteger i, NSInteger j, CGFloat eps, BOOL *keep) {
    if (j <= i + 1) return;
    CGFloat dmax = 0;
    NSInteger idx = -1;
    for (NSInteger k = i + 1; k < j; k++) {
        CGFloat d = STSegDist(p[k], p[i], p[j]);
        if (d > dmax) { dmax = d; idx = k; }
    }
    if (idx >= 0 && dmax > eps) {
        keep[idx] = YES;
        STDP(p, i, idx, eps, keep);
        STDP(p, idx, j, eps, keep);
    }
}

static inline NSValue *STV(CGPoint p) { return [NSValue valueWithCGPoint:p]; }

static NSArray<NSValue *> *STEllipsePts(CGRect r) {
    NSMutableArray *a = [NSMutableArray array];
    CGFloat cx = CGRectGetMidX(r), cy = CGRectGetMidY(r), rx = r.size.width / 2, ry = r.size.height / 2;
    for (int i = 0; i <= 72; i++) {
        double t = 2 * M_PI * i / 72.0 - M_PI_2;
        [a addObject:STV(CGPointMake(cx + rx * cos(t), cy + ry * sin(t)))];
    }
    return a;
}

static NSArray<NSValue *> *STRectPts(CGRect r) {
    return @[STV(CGPointMake(CGRectGetMinX(r), CGRectGetMinY(r))), STV(CGPointMake(CGRectGetMaxX(r), CGRectGetMinY(r))),
             STV(CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r))), STV(CGPointMake(CGRectGetMinX(r), CGRectGetMaxY(r))),
             STV(CGPointMake(CGRectGetMinX(r), CGRectGetMinY(r)))];
}

static NSArray<NSValue *> *STArrowPts(CGPoint a, CGPoint b, CGFloat head) {
    CGFloat d = STDist(a, b);
    head = MIN(head, d * 0.5);
    CGFloat ang = atan2(b.y - a.y, b.x - a.x), sp = 28.0 * M_PI / 180.0;
    CGPoint l = CGPointMake(b.x - head * cos(ang - sp), b.y - head * sin(ang - sp));
    CGPoint r = CGPointMake(b.x - head * cos(ang + sp), b.y - head * sin(ang + sp));
    return @[STV(a), STV(b), STV(l), STV(b), STV(r)];
}

static CGFloat STTurn(CGPoint a, CGPoint b, CGPoint c) {
    CGFloat x1 = b.x - a.x, y1 = b.y - a.y, x2 = c.x - b.x, y2 = c.y - b.y;
    return atan2(fabs(x1 * y2 - y1 * x2), x1 * x2 + y1 * y2);
}

// Nhận dạng nét vẽ tay (toạ độ chuẩn hoá) -> các điểm hình hoàn chỉnh (toạ độ canvas), hoặc nil.
static NSArray<NSValue *> *STRecognize(NSArray<NSValue *> *norm, CGSize size) {
    NSUInteger n = norm.count;
    if (n < 6) return nil;
    NSMutableData *pd = [NSMutableData dataWithLength:n * sizeof(CGPoint)];
    CGPoint *p = pd.mutableBytes;
    CGFloat L = 0, minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
    for (NSUInteger i = 0; i < n; i++) {
        CGPoint q = norm[i].CGPointValue;
        p[i] = CGPointMake(q.x * size.width, q.y * size.height);
        minX = MIN(minX, p[i].x); maxX = MAX(maxX, p[i].x);
        minY = MIN(minY, p[i].y); maxY = MAX(maxY, p[i].y);
        if (i) L += STDist(p[i - 1], p[i]);
    }
    CGFloat w = maxX - minX, h = maxY - minY, diag = hypot(w, h);
    if (L < 40 || diag < 25) return nil;
    CGFloat gap = STDist(p[0], p[n - 1]);

    // --- nét hở: đường thẳng
    if (gap > 0.35 * L) {
        if (gap < 30) return nil;
        CGFloat dev = 0;
        for (NSUInteger k = 0; k < n; k++) dev = MAX(dev, STSegDist(p[k], p[0], p[n - 1]));
        return dev <= 0.07 * gap ? @[STV(p[0]), STV(p[n - 1])] : nil;
    }
    if (gap > 0.22 * L) return nil;
    if (MIN(w, h) < 0.15 * MAX(w, h)) return nil;

    // --- nét khép kín: đa giác (3-4 đỉnh) hoặc elip
    NSMutableData *kd = [NSMutableData dataWithLength:n];
    BOOL *keep = kd.mutableBytes;
    keep[0] = keep[n - 1] = YES;
    STDP(p, 0, (NSInteger)n - 1, 0.07 * diag, keep);
    NSMutableArray<NSValue *> *V = [NSMutableArray array];
    for (NSUInteger i = 0; i + 1 < n; i++) if (keep[i]) [V addObject:STV(p[i])];

    // bỏ đỉnh gần thẳng hàng / quá gần nhau
    BOOL changed = YES;
    while (changed && V.count > 3) {
        changed = NO;
        NSUInteger cnt = V.count, worst = 0;
        CGFloat wt = 1e9;
        for (NSUInteger i = 0; i < cnt; i++) {
            CGFloat t = STTurn(V[(i + cnt - 1) % cnt].CGPointValue, V[i].CGPointValue, V[(i + 1) % cnt].CGPointValue);
            if (t < wt) { wt = t; worst = i; }
        }
        if (wt < 0.44) { [V removeObjectAtIndex:worst]; changed = YES; continue; }
        for (NSUInteger i = 0; i < cnt; i++) {
            if (STDist(V[i].CGPointValue, V[(i + 1) % cnt].CGPointValue) < 0.1 * diag) {
                [V removeObjectAtIndex:(i + 1) % cnt];
                changed = YES;
                break;
            }
        }
    }

    NSUInteger vc = V.count;
    if (vc == 3 || vc == 4) {
        CGFloat sum = 0;
        for (NSUInteger k = 0; k < n; k++) {
            CGFloat best = 1e9;
            for (NSUInteger i = 0; i < vc; i++) best = MIN(best, STSegDist(p[k], V[i].CGPointValue, V[(i + 1) % vc].CGPointValue));
            sum += best;
        }
        if (sum / n / diag < 0.045) {
            if (vc == 3) return @[V[0], V[1], V[2], V[0]];
            BOOL aligned = YES;
            for (NSUInteger i = 0; i < 4; i++) {
                CGPoint a = V[i].CGPointValue, b = V[(i + 1) % 4].CGPointValue;
                CGFloat ang = fmod(fabs(atan2(b.y - a.y, b.x - a.x)), M_PI_2);
                if (MIN(ang, M_PI_2 - ang) > 0.3) aligned = NO;
            }
            if (!aligned) return @[V[0], V[1], V[2], V[3], V[0]];
            CGRect r = CGRectMake(minX, minY, w, h);
            if (fabs(w - h) < 0.12 * MAX(w, h)) { // hình vuông
                CGFloat s = (w + h) / 2;
                r = CGRectMake(CGRectGetMidX(r) - s / 2, CGRectGetMidY(r) - s / 2, s, s);
            }
            return STRectPts(r);
        }
    }

    CGFloat cx = (minX + maxX) / 2, cy = (minY + maxY) / 2, a = w / 2, b = h / 2, err = 0;
    for (NSUInteger k = 0; k < n; k++) err += fabs(hypot((p[k].x - cx) / a, (p[k].y - cy) / b) - 1);
    if (err / n < 0.14) {
        CGRect r = CGRectMake(minX, minY, w, h);
        if (fabs(w - h) < 0.12 * MAX(w, h)) { // hình tròn
            CGFloat s = (w + h) / 2;
            r = CGRectMake(cx - s / 2, cy - s / 2, s, s);
        }
        return STEllipsePts(r);
    }
    return nil;
}

#pragma mark - Drawing editor

// Nét vẽ lưu theo toạ độ chuẩn hoá (0..1) nên vẽ lại được ở mọi kích thước.
static void STDrawStrokes(NSArray<NSDictionary *> *strokes, CGSize size) {
    for (NSDictionary *s in strokes) {
        if ([s[@"type"] isEqual:@"text"]) {
            CGPoint pos = [s[@"pos"] CGPointValue];
            UIFont *font = [UIFont systemFontOfSize:[s[@"fs"] doubleValue] * size.width weight:UIFontWeightBold];
            [(NSString *)s[@"text"] drawAtPoint:CGPointMake(pos.x * size.width, pos.y * size.height)
                                 withAttributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: s[@"color"] }];
            continue;
        }
        NSArray<NSValue *> *pts = s[@"pts"];
        if (pts.count == 0) continue;
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        p.lineWidth = [s[@"w"] doubleValue] * size.width;
        CGPoint f = pts[0].CGPointValue;
        CGPoint first = CGPointMake(f.x * size.width, f.y * size.height);
        [p moveToPoint:first];
        if (pts.count == 1) {
            [p addLineToPoint:CGPointMake(first.x + 0.01, first.y)];
        } else {
            for (NSUInteger i = 1; i < pts.count; i++) {
                CGPoint q = pts[i].CGPointValue;
                [p addLineToPoint:CGPointMake(q.x * size.width, q.y * size.height)];
            }
        }
        [[(UIColor *)s[@"color"] colorWithAlphaComponent:[s[@"a"] doubleValue]] setStroke];
        [p stroke];
    }
}

typedef NS_ENUM(NSInteger, STTool) { STToolPen = 0, STToolRect, STToolEllipse, STToolArrow, STToolText };

@interface STCanvas : UIView
@property (nonatomic, strong) UIColor *color;
@property (nonatomic) CGFloat widthPt;
@property (nonatomic) CGFloat alphaValue;
@property (nonatomic) CGFloat fontPt;
@property (nonatomic) STTool tool;
@property (nonatomic, copy) void (^onTextTap)(CGPoint p);
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *strokes;
- (void)undo;
@end

@implementation STCanvas {
    NSMutableArray<NSValue *> *_curPts;
    NSTimer *_hold;
    CGPoint _start, _anchor;
    BOOL _snapped;
}
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    _strokes = [NSMutableArray array];
    _color = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:1];
    _widthPt = 4;
    _alphaValue = 1;
    _fontPt = 24;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.multipleTouchEnabled = NO;
    return self;
}
- (NSValue *)nv:(CGPoint)p {
    CGSize s = self.bounds.size;
    if (s.width <= 0 || s.height <= 0) return STV(CGPointZero);
    return STV(CGPointMake(MIN(MAX(p.x / s.width, 0), 1), MIN(MAX(p.y / s.height, 0), 1)));
}
- (void)setCurrentFromCanvasPoints:(NSArray<NSValue *> *)pts {
    [_curPts removeAllObjects];
    for (NSValue *v in pts) [_curPts addObject:[self nv:v.CGPointValue]];
}
- (void)restartHold {
    [_hold invalidate];
    _hold = [NSTimer scheduledTimerWithTimeInterval:0.55 target:self selector:@selector(holdFired) userInfo:nil repeats:NO];
}
- (void)holdFired {
    _hold = nil;
    if (!_curPts || _snapped || _tool != STToolPen) return;
    NSArray<NSValue *> *shape = STRecognize(_curPts, self.bounds.size);
    if (!shape) return;
    [self setCurrentFromCanvasPoints:shape];
    _snapped = YES;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    [self setNeedsDisplay];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    if (_curPts || self.bounds.size.width <= 0) return;
    CGPoint p = [touches.anyObject locationInView:self];
    if (_tool == STToolText) { if (self.onTextTap) self.onTextTap(p); return; }
    _start = _anchor = p;
    _snapped = NO;
    _curPts = [NSMutableArray arrayWithObject:[self nv:p]];
    [_strokes addObject:@{ @"pts": _curPts, @"color": self.color,
                           @"w": @(self.widthPt / self.bounds.size.width), @"a": @(self.alphaValue) }];
    if (_tool == STToolPen) [self restartHold];
    [self setNeedsDisplay];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    if (!_curPts || _snapped) return;
    CGPoint p = [touches.anyObject locationInView:self];
    if (_tool == STToolPen) {
        [_curPts addObject:[self nv:p]];
        if (STDist(p, _anchor) > 4) { _anchor = p; [self restartHold]; }
    } else {
        CGRect r = CGRectStandardize(CGRectMake(_start.x, _start.y, p.x - _start.x, p.y - _start.y));
        NSArray<NSValue *> *pts = nil;
        if (_tool == STToolRect) pts = STRectPts(r);
        else if (_tool == STToolEllipse) pts = STEllipsePts(r);
        else if (_tool == STToolArrow) pts = STArrowPts(_start, p, MAX(14, self.widthPt * 4.5));
        if (pts) [self setCurrentFromCanvasPoints:pts];
    }
    [self setNeedsDisplay];
}
- (void)endTouch {
    [_hold invalidate];
    _hold = nil;
    if (_curPts) {
        if (_curPts.count == 1) {
            if (_tool == STToolPen) [_curPts addObject:_curPts[0]];   // chạm 1 lần = chấm tròn
            else [_strokes removeLastObject];                         // hình chưa kéo -> bỏ
        }
        _curPts = nil;
        [self setNeedsDisplay];
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e { [self endTouch]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e { [self endTouch]; }
- (void)undo {
    if (_curPts) return;
    [_strokes removeLastObject];
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect { STDrawStrokes(_strokes, self.bounds.size); }
@end

@interface STEditView : UIView <UITextFieldDelegate>
@property (nonatomic, copy) void (^onDone)(UIImage *result); // nil = hủy
- (instancetype)initWithImage:(UIImage *)image frame:(CGRect)frame;
@end

@implementation STEditView {
    UIImage *_image;
    UIView *_content;
    UIImageView *_iv;
    STCanvas *_canvas;
    UIButton *_cancelBtn, *_shareBtn, *_undoBtn, *_sizeBtn;
    NSArray<UIButton *> *_colorBtns, *_toolBtns;
    NSArray<UIColor *> *_colors;
    NSInteger _colorIdx, _sizeIdx;
    STTool _tool;
    UITextField *_field;
    UIWindow *_prevKey;
    BOOL _finished;
}

- (instancetype)initWithImage:(UIImage *)image frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _image = image;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];

    _content = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:_content];
    _iv = [[UIImageView alloc] initWithImage:image];
    [_content addSubview:_iv];
    _canvas = [[STCanvas alloc] initWithFrame:CGRectZero];
    __weak typeof(self) ws = self;
    _canvas.onTextTap = ^(CGPoint p) { [ws textTapAt:p]; };
    [_content addSubview:_canvas];

    UIColor *dark = [UIColor colorWithWhite:1 alpha:0.18];
    _cancelBtn = STRoundButton(@"xmark", dark, 40);
    [_cancelBtn addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    _shareBtn = STRoundButton(@"checkmark", [UIColor colorWithRed:0.18 green:0.7 blue:0.35 alpha:1], 40);
    [_shareBtn addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
    _undoBtn = STRoundButton(@"arrow.uturn.backward", dark, 36);
    [_undoBtn addTarget:self action:@selector(undoTap) forControlEvents:UIControlEventTouchUpInside];
    _sizeBtn = STRoundButton(nil, dark, 36);
    _sizeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [_sizeBtn addTarget:self action:@selector(cycleSize) forControlEvents:UIControlEventTouchUpInside];

    // màu cuối (vàng) là bút dạ quang
    _colors = @[ [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:1],
                 [UIColor colorWithRed:0.2 green:0.5 blue:1 alpha:1],
                 [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1],
                 [UIColor whiteColor],
                 [UIColor colorWithRed:1 green:0.88 blue:0 alpha:1] ];
    NSMutableArray *cb = [NSMutableArray array];
    for (NSUInteger i = 0; i < _colors.count; i++) {
        UIButton *b = STRoundButton(nil, _colors[i], 30);
        b.layer.borderColor = UIColor.whiteColor.CGColor;
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(pickColor:) forControlEvents:UIControlEventTouchUpInside];
        [cb addObject:b];
        [self addSubview:b];
    }
    _colorBtns = cb;

    NSArray *toolSymbols = @[@"pencil.tip", @"square", @"circle", @"arrow.up.right", @"textformat"];
    NSMutableArray *tb = [NSMutableArray array];
    for (NSUInteger i = 0; i < toolSymbols.count; i++) {
        UIButton *b = STRoundButton(toolSymbols[i], dark, 38);
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(pickTool:) forControlEvents:UIControlEventTouchUpInside];
        [tb addObject:b];
        [self addSubview:b];
    }
    _toolBtns = tb;
    for (UIView *v in @[_cancelBtn, _shareBtn, _undoBtn, _sizeBtn]) [self addSubview:v];

    _colorIdx = 0;
    _sizeIdx = 1;
    _tool = STToolPen;
    [self applyTool];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(kbChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)applyTool {
    static const CGFloat sizes[3] = {3, 6, 10};
    static const CGFloat fonts[3] = {16, 24, 36};
    BOOL hl = (_colorIdx == (NSInteger)_colors.count - 1);
    _canvas.tool = _tool;
    _canvas.color = _colors[_colorIdx];
    _canvas.alphaValue = hl ? 0.4 : 1;
    _canvas.widthPt = sizes[_sizeIdx] * (hl ? 3 : 1);
    _canvas.fontPt = fonts[_sizeIdx];
    [_sizeBtn setTitle:@[@"S", @"M", @"L"][_sizeIdx] forState:UIControlStateNormal];
    for (UIButton *b in _colorBtns) {
        BOOL sel = (b.tag == _colorIdx);
        b.layer.borderWidth = sel ? 3 : 1;
        b.transform = sel ? CGAffineTransformMakeScale(1.15, 1.15) : CGAffineTransformIdentity;
    }
    for (UIButton *b in _toolBtns) {
        b.backgroundColor = (b.tag == (NSInteger)_tool) ? [UIColor colorWithWhite:1 alpha:0.55] : [UIColor colorWithWhite:1 alpha:0.18];
    }
    if (_field) _field.textColor = _colors[_colorIdx];
}
- (void)pickColor:(UIButton *)b { _colorIdx = b.tag; [self applyTool]; }
- (void)pickTool:(UIButton *)b { [self commitText]; _tool = (STTool)b.tag; [self applyTool]; }
- (void)cycleSize { [self commitText]; _sizeIdx = (_sizeIdx + 1) % 3; [self applyTool]; }
- (void)undoTap { [self commitText]; [_canvas undo]; }

#pragma mark text

- (void)textTapAt:(CGPoint)pc {
    if (_field) { [self commitText]; return; }
    CGSize cs = _canvas.bounds.size;
    CGFloat fh = ceil(_canvas.fontPt * 1.5);
    CGFloat x = MIN(MAX(pc.x, 0), MAX(cs.width - 80, 0));
    CGFloat y = MIN(MAX(pc.y - fh / 2, 0), MAX(cs.height - fh, 0));
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(x, y, cs.width - x, fh)];
    tf.font = [UIFont systemFontOfSize:_canvas.fontPt weight:UIFontWeightBold];
    tf.textColor = _colors[_colorIdx];
    tf.tintColor = _colors[_colorIdx];
    tf.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    tf.borderStyle = UITextBorderStyleNone;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = self;
    [_canvas addSubview:tf];
    _field = tf;

    UIWindow *w = self.window;
    if (w) {
        if (!_prevKey) {
            for (UIWindow *x2 in w.windowScene.windows) if (x2.isKeyWindow && x2 != w) _prevKey = x2;
        }
        [w makeKeyWindow]; // cần là key window thì bàn phím mới hiện
    }
    [tf becomeFirstResponder];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self commitText]; return NO; }

- (void)commitText {
    if (!_field) return;
    UITextField *tf = _field;
    _field = nil;
    NSString *t = tf.text;
    CGSize cs = _canvas.bounds.size;
    if (t.length > 0 && cs.width > 0 && cs.height > 0) {
        UIFont *font = tf.font;
        CGFloat lh = font.lineHeight;
        CGPoint pos = CGPointMake(tf.frame.origin.x / cs.width, (tf.frame.origin.y + (tf.frame.size.height - lh) / 2) / cs.height);
        [_canvas.strokes addObject:@{ @"type": @"text", @"text": t, @"pos": STV(pos),
                                      @"color": tf.textColor ?: UIColor.whiteColor, @"fs": @(font.pointSize / cs.width) }];
    }
    [tf resignFirstResponder];
    [tf removeFromSuperview];
    [_prevKey makeKeyWindow];
    _prevKey = nil;
    [UIView animateWithDuration:0.25 animations:^{ self->_content.transform = CGAffineTransformIdentity; }];
    [_canvas setNeedsDisplay];
}

- (void)kbChange:(NSNotification *)n {
    if (!_field) return;
    CGRect kb = [self convertRect:[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    NSTimeInterval dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGRect fr = [_canvas convertRect:_field.frame toView:self];
    CGFloat overlap = MAX(0, CGRectGetMaxY(fr) - _content.transform.ty + 14 - kb.origin.y);
    if (kb.origin.y >= self.bounds.size.height) overlap = 0;
    [UIView animateWithDuration:dur animations:^{ self->_content.transform = CGAffineTransformMakeTranslation(0, -overlap); }];
}

#pragma mark layout / output

- (void)layoutSubviews {
    [super layoutSubviews];
    CGAffineTransform t = _content.transform;
    _content.transform = CGAffineTransformIdentity;
    _content.frame = self.bounds;
    _content.transform = t;

    UIEdgeInsets s = self.safeAreaInsets;
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    _cancelBtn.center = CGPointMake(s.left + 34, s.top + 32);
    _shareBtn.center = CGPointMake(W - s.right - 34, s.top + 32);

    CGFloat tbY = H - s.bottom - 28;      // hàng dưới: undo, màu, cỡ nét
    CGFloat toolY = tbY - 48;             // hàng trên: công cụ
    NSMutableArray<UIView *> *items = [NSMutableArray arrayWithObject:_undoBtn];
    [items addObjectsFromArray:_colorBtns];
    [items addObject:_sizeBtn];
    CGFloat gap = 10, total = gap * (items.count - 1);
    for (UIView *v in items) total += v.bounds.size.width;
    CGFloat x = (W - total) / 2;
    for (UIView *v in items) {
        v.center = CGPointMake(x + v.bounds.size.width / 2, tbY);
        x += v.bounds.size.width + gap;
    }
    gap = 14;
    total = gap * (_toolBtns.count - 1);
    for (UIView *v in _toolBtns) total += v.bounds.size.width;
    x = (W - total) / 2;
    for (UIView *v in _toolBtns) {
        v.center = CGPointMake(x + v.bounds.size.width / 2, toolY);
        x += v.bounds.size.width + gap;
    }

    CGFloat top = s.top + 72, bottom = toolY - 19 - 10;
    CGRect area = CGRectMake(s.left + 12, top, W - s.left - s.right - 24, bottom - top);
    CGSize is = _image.size;
    if (area.size.width <= 0 || area.size.height <= 0 || is.width <= 0 || is.height <= 0) return;
    CGFloat sc = MIN(MIN(area.size.width / is.width, area.size.height / is.height), 3);
    CGSize fit = CGSizeMake(floor(is.width * sc), floor(is.height * sc));
    CGRect r = CGRectMake(floor(CGRectGetMidX(area) - fit.width / 2), floor(CGRectGetMidY(area) - fit.height / 2), fit.width, fit.height);
    _iv.frame = r;
    _canvas.frame = r;
    [_canvas setNeedsDisplay];
}

- (UIImage *)render {
    if (_canvas.strokes.count == 0) return _image;
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = _image.scale;
    CGSize size = _image.size;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:f];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [self->_image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        STDrawStrokes(self->_canvas.strokes, size);
    }];
}

- (void)finish {
    if (_finished) return;
    [self commitText];
    _finished = YES;
    if (self.onDone) self.onDone([self render]);
}
- (void)cancel {
    if (_finished) return;
    [self commitText];
    _finished = YES;
    if (self.onDone) self.onDone(nil);
}
@end

#pragma mark - Manager

@interface STManager : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)start;
@end

@implementation STManager {
    STWindow *_window;
    STRootVC *_root;
    STButton *_button;
    STSnipView *_snip;
    STEditView *_edit;
    BOOL _userHidden;
    CGPoint _frac;
}

+ (instancetype)shared {
    static STManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [STManager new]; });
    return m;
}

- (void)start {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    _userHidden = [d boolForKey:kHidden];
    _frac = CGPointMake([d objectForKey:kFX] ? [d floatForKey:kFX] : 0.90,
                        [d objectForKey:kFY] ? [d floatForKey:kFY] : 0.18);
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(refresh) name:UIWindowDidBecomeVisibleNotification object:nil];
    [nc addObserver:self selector:@selector(refresh) name:UISceneDidActivateNotification object:nil];
    // dự phòng: một số app (nhất là app hệ thống) có thể lỡ thông báo -> thử lại mỗi giây
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [self refresh];
}

- (UIWindowScene *)activeScene {
    UIWindowScene *inactive = nil, *any = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
        if (s.activationState == UISceneActivationStateForegroundInactive) inactive = (UIWindowScene *)s;
        if (!any) any = (UIWindowScene *)s;
    }
    return inactive ?: any;
}

- (void)refresh {
    if (_window && _window.windowScene == nil) { _window = nil; _root = nil; _button = nil; _snip = nil; _edit = nil; }
    UIWindowScene *scene = _window ? _window.windowScene : [self activeScene];
    if (!scene) return;
    if (!_window) [self buildWindowInScene:scene];
    for (UIWindow *w in scene.windows) [self attachGestureTo:w];
}

- (void)buildWindowInScene:(UIWindowScene *)scene {
    __weak typeof(self) ws = self;
    _root = [STRootVC new];
    _root.onLayout = ^{ [ws layoutButton]; };

    _window = [[STWindow alloc] initWithWindowScene:scene];
    _window.windowLevel = UIWindowLevelAlert + 1000;
    _window.backgroundColor = UIColor.clearColor;
    _window.rootViewController = _root;
    _window.hidden = NO; // không makeKey để app vẫn giữ key window

    _button = [STButton new];
    _button.alpha = _userHidden ? 0 : 1;
    _button.hidden = _userHidden;
    [_button addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapButton)]];
    [_button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panButton:)]];
    [_root.view addSubview:_button];
    [self layoutButton];
}

- (void)layoutButton {
    if (!_button || _snip || _edit) return;
    UIView *v = _root.view;
    CGRect b = v.bounds;
    UIEdgeInsets s = v.safeAreaInsets;
    CGFloat m = kBtnSize / 2 + 4;
    CGFloat x = _frac.x * b.size.width, y = _frac.y * b.size.height;
    x = MIN(MAX(x, s.left + m), b.size.width - s.right - m);
    y = MIN(MAX(y, s.top + m), b.size.height - s.bottom - m);
    _button.center = CGPointMake(x, y);
}

- (void)panButton:(UIPanGestureRecognizer *)g {
    UIView *v = _root.view;
    CGPoint t = [g translationInView:v];
    _button.center = CGPointMake(_button.center.x + t.x, _button.center.y + t.y);
    [g setTranslation:CGPointZero inView:v];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGSize sz = v.bounds.size;
        if (sz.width > 0 && sz.height > 0) {
            _frac = CGPointMake(_button.center.x / sz.width, _button.center.y / sz.height);
            NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
            [d setFloat:_frac.x forKey:kFX];
            [d setFloat:_frac.y forKey:kFY];
        }
        [self layoutButton];
    }
}

#pragma mark 3-finger double tap

- (void)attachGestureTo:(UIWindow *)w {
    if (!w || [w isKindOfClass:STWindow.class]) return;
    if (w.windowLevel != UIWindowLevelNormal) return;
    if (objc_getAssociatedObject(w, kAttachedKey)) return;
    UITapGestureRecognizer *g = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle:)];
    g.numberOfTapsRequired = 2;
    g.numberOfTouchesRequired = 3;
    g.cancelsTouchesInView = NO;
    g.delaysTouchesBegan = NO;
    g.delaysTouchesEnded = NO;
    g.delegate = self;
    [w addGestureRecognizer:g];
    objc_setAssociatedObject(w, kAttachedKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}

- (void)toggle:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded || _snip || _edit || !_button) return;
    _userHidden = !_userHidden;
    [NSUserDefaults.standardUserDefaults setBool:_userHidden forKey:kHidden];
    [[UIImpactFeedbackGenerator new] impactOccurred];
    if (!_userHidden) { _button.hidden = NO; [self layoutButton]; }
    [UIView animateWithDuration:0.2 animations:^{ self->_button.alpha = self->_userHidden ? 0 : 1; }
                     completion:^(BOOL f) { self->_button.hidden = self->_userHidden; }];
}

#pragma mark Snip

- (UIImage *)captureScene {
    UIWindowScene *scene = _window.windowScene;
    if (!scene) return nil;
    CGRect bounds = _window.bounds;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = scene.screen.scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:bounds.size format:fmt];
    NSArray<UIWindow *> *wins = [scene.windows sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        return a.windowLevel < b.windowLevel ? NSOrderedAscending : (a.windowLevel > b.windowLevel ? NSOrderedDescending : NSOrderedSame);
    }];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        for (UIWindow *w in wins) {
            if (w == self->_window || w.hidden || w.alpha == 0) continue;
            [w drawViewHierarchyInRect:w.frame afterScreenUpdates:YES];
        }
    }];
}

- (void)tapButton {
    if (_snip || _edit) return;
    UIImage *shot = [self captureScene];
    if (!shot) return;
    _button.hidden = YES;
    STSnipView *v = [[STSnipView alloc] initWithImage:shot frame:_root.view.bounds];
    __weak typeof(self) ws = self;
    v.onDone = ^(CGRect r) { [ws finishSnipWithImage:shot rect:r]; };
    [_root.view addSubview:v];
    _snip = v;
}

- (void)restoreButton {
    _button.hidden = _userHidden;
    [self layoutButton];
}

- (void)finishSnipWithImage:(UIImage *)img rect:(CGRect)r {
    [_snip removeFromSuperview];
    _snip = nil;
    if (CGRectIsNull(r) || CGRectIsEmpty(r)) { [self restoreButton]; return; }

    CGFloat s = img.scale;
    CGRect px = CGRectIntegral(CGRectMake(r.origin.x * s, r.origin.y * s, r.size.width * s, r.size.height * s));
    CGImageRef c = CGImageCreateWithImageInRect(img.CGImage, px);
    if (!c) { [self restoreButton]; return; }
    UIImage *out = [UIImage imageWithCGImage:c scale:s orientation:UIImageOrientationUp];
    CGImageRelease(c);

    STEditView *e = [[STEditView alloc] initWithImage:out frame:_root.view.bounds];
    __weak typeof(self) ws = self;
    e.onDone = ^(UIImage *result) { [ws finishEditWithImage:result]; };
    [_root.view addSubview:e];
    _edit = e;
}

- (void)finishEditWithImage:(UIImage *)result {
    [_edit removeFromSuperview];
    _edit = nil;
    [self restoreButton];
    if (!result) return;

    UIPasteboard.generalPasteboard.image = result;
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[result] applicationActivities:nil];
    a.popoverPresentationController.sourceView = _root.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(_root.view.bounds), CGRectGetMidY(_root.view.bounds), 1, 1);
    [_root presentViewController:a animated:YES completion:nil];
}
@end

__attribute__((constructor))
static void st_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[STManager shared] start]; });
}
