// SnipTool.m v4 - floating "Rectangular Snip" button for injected iOS apps
// - Nút 38pt, kéo di chuyển được; chạm để chụp & crop vùng chọn; GIỮ nút ~0.5s = chụp toàn màn hình ngay
// - Màn chọn vùng có nút ⤢ để chụp toàn màn hình
// - Sau khi chụp: vẽ lên ảnh
//     bút tay (giữ yên ngón tay ~0.45s để tự sửa nét: đường thẳng / hình chữ nhật / vuông / tròn / elip / tam giác)
//     hình chữ nhật, hình elip/tròn, mũi tên (kéo để vẽ)
//     nhập chữ: chạm để chọn -> kéo để di chuyển, kéo góc dưới phải / chụm 2 ngón để đổi cỡ, chạm lần nữa để sửa chữ
//     5 màu (màu vàng = bút dạ quang), 3 cỡ nét, undo
//     nút dịch: OCR (Vision) + dịch sang tiếng Việt rồi vẽ đè lên ảnh
// - Chạm 3 ngón 2 lần: ẩn / hiện nút (trạng thái được lưu)
// - Kết quả: copy vào clipboard + mở share sheet (chọn "Save Image" để lưu vào Ảnh)

#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <objc/runtime.h>

static NSString *const kFX = @"SnipTool.fx";
static NSString *const kFY = @"SnipTool.fy";
static NSString *const kHidden = @"SnipTool.hidden";
static const void *kAttachedKey = &kAttachedKey;

static const CGFloat kBtnSize = 38;

static UIButton *STRoundButtonAny(NSArray<NSString *> *symbols, UIColor *bg, CGFloat size) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, size, size);
    b.backgroundColor = bg;
    b.layer.cornerRadius = size / 2;
    b.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.4 weight:UIImageSymbolWeightBold];
    for (NSString *s in symbols) {   // thử lần lượt: symbol nào hệ thống có thì dùng
        UIImage *img = [UIImage systemImageNamed:s withConfiguration:c];
        if (img) { [b setImage:img forState:UIControlStateNormal]; break; }
    }
    return b;
}

static UIButton *STRoundButton(NSString *symbol, UIColor *bg, CGFloat size) {
    return STRoundButtonAny(symbol ? @[symbol] : @[], bg, size);
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
    UIButton *_ok, *_no, *_close, *_full;
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
    _hint.text = @"Kéo chọn vùng · bấm ⤢ chụp toàn màn hình";
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

    // chụp nhanh toàn màn hình
    _full = STRoundButtonAny(@[@"arrow.up.left.and.arrow.down.right", @"viewfinder", @"rectangle.dashed"],
                             [UIColor colorWithRed:0.2 green:0.5 blue:1 alpha:0.9], 34);
    [_full addTarget:self action:@selector(fullScreen) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_full];

    _ok =STRoundButton(@"checkmark", [UIColor colorWithRed:0.18 green:0.7 blue:0.35 alpha:0.95], 40);
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
    _hint.frame = CGRectMake((self.bounds.size.width - 236) / 2, s.top + 12, 236, 28);
    _close.center = CGPointMake(self.bounds.size.width - s.right - 30, s.top + 26);
    _full.center = CGPointMake(s.left + 30, s.top + 26);
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
- (void)fullScreen {
    if (_finished) return;
    _finished = YES;
    if (self.onDone) self.onDone(self.bounds);
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
    if (gap > 0.28 * L) return nil;
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
    if (err / n < 0.16) {
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

// Chữ lưu theo toạ độ chuẩn hoá: pos = góc trên-trái (0..1), fs = cỡ chữ / bề rộng ảnh.
static void STDrawText(NSString *text, CGPoint pos, CGFloat fs, UIColor *color, CGSize size) {
    UIFont *font = [UIFont systemFontOfSize:fs * size.width weight:UIFontWeightBold];
    [text drawAtPoint:CGPointMake(pos.x * size.width, pos.y * size.height)
       withAttributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: color }];
}

// Nét vẽ lưu theo toạ độ chuẩn hoá (0..1) nên vẽ lại được ở mọi kích thước.
static void STDrawStrokes(NSArray<NSDictionary *> *strokes, CGSize size) {
    for (NSDictionary *s in strokes) {
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

static const NSTimeInterval kHoldSeconds = 0.45;   // giữ yên cuối nét bao lâu thì tự sửa

#pragma mark - Canvas (bút / hình)

@interface STCanvas : UIView
@property (nonatomic, strong) UIColor *color;
@property (nonatomic) CGFloat widthPt;
@property (nonatomic) CGFloat alphaValue;
@property (nonatomic) CGFloat fontPt;
@property (nonatomic) STTool tool;
@property (nonatomic, copy) BOOL (^onBackgroundTouch)(void);   // trả YES nếu vừa bỏ chọn / chốt chữ
@property (nonatomic, copy) void (^onTextTap)(CGPoint p);
@property (nonatomic, copy) void (^onStrokeDone)(void);
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
    _hold = [NSTimer timerWithTimeInterval:kHoldSeconds target:self selector:@selector(holdFired) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:_hold forMode:NSRunLoopCommonModes];
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
    BOOL consumed = self.onBackgroundTouch ? self.onBackgroundTouch() : NO;
    if (_tool == STToolText) { if (!consumed && self.onTextTap) self.onTextTap(p); return; }
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
        if (STDist(p, _anchor) > 6) { _anchor = p; [self restartHold]; }   // run tay nhẹ không tính là di chuyển
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
        BOOL keep = YES;
        if (_curPts.count == 1) {
            if (_tool == STToolPen) [_curPts addObject:_curPts[0]];   // chạm 1 lần = chấm tròn
            else { [_strokes removeLastObject]; keep = NO; }          // hình chưa kéo -> bỏ
        }
        _curPts = nil;
        if (keep && self.onStrokeDone) self.onStrokeDone();
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

#pragma mark - Chữ: kéo di chuyển / đổi cỡ

@interface STPassView : UIView   // view trong suốt, chỉ nhận chạm ở các view con
@end
@implementation STPassView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return v == self ? nil : v;
}
@end

static const CGFloat kTBPad = 18;

@interface STTextBox : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic) CGFloat fs;          // cỡ chữ / bề rộng canvas
@property (nonatomic) CGPoint pos;         // góc trên-trái của chữ, chuẩn hoá 0..1
@property (nonatomic) CGSize canvasSize;
@property (nonatomic) BOOL selected;
@property (nonatomic, copy) void (^onSelect)(STTextBox *);
@property (nonatomic, copy) void (^onEdit)(STTextBox *);
@property (nonatomic, copy) void (^onDelete)(STTextBox *);
- (void)relayout;
- (void)setFsClamped:(CGFloat)v;
- (NSDictionary *)model;
@end

@implementation STTextBox {
    UILabel *_label;
    CAShapeLayer *_dash;
    UIButton *_del, *_handle;
    CGFloat _startFs, _startDist;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    _label = [UILabel new];
    _label.numberOfLines = 1;
    [self addSubview:_label];

    _dash = [CAShapeLayer layer];
    _dash.fillColor = nil;
    _dash.strokeColor = [UIColor colorWithWhite:1 alpha:0.95].CGColor;
    _dash.lineWidth = 1.2;
    _dash.lineDashPattern = @[@4, @3];
    _dash.hidden = YES;
    [self.layer addSublayer:_dash];

    _del = STRoundButton(@"xmark", [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:1], 24);
    [_del addTarget:self action:@selector(delTap) forControlEvents:UIControlEventTouchUpInside];
    _del.hidden = YES;
    [self addSubview:_del];

    _handle = STRoundButtonAny(@[@"arrow.up.left.and.arrow.down.right", @"arrow.up.backward.and.arrow.down.forward", @"plus"],
                               [UIColor colorWithRed:0.2 green:0.5 blue:1 alpha:1], 26);
    _handle.hidden = YES;
    [_handle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panHandle:)]];
    [self addSubview:_handle];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    tap.delegate = self;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panSelf:)];
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
    pinch.delegate = self;
    [self addGestureRecognizer:tap];
    [self addGestureRecognizer:pan];
    [self addGestureRecognizer:pinch];
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    return !([t.view isDescendantOfView:_handle] || [t.view isDescendantOfView:_del]);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    CGRect r = _selected ? self.bounds : CGRectInset(self.bounds, kTBPad - 6, kTBPad - 6);
    return CGRectContainsPoint(r, p);
}

- (void)setSelected:(BOOL)s {
    _selected = s;
    _dash.hidden = _del.hidden = _handle.hidden = !s;
}

- (void)setFsClamped:(CGFloat)v {
    CGFloat cw = MAX(_canvasSize.width, 1);
    _fs = MIN(MAX(v, 8.0 / cw), 260.0 / cw);
}

- (void)relayout {
    CGFloat cw = _canvasSize.width, ch = _canvasSize.height;
    if (cw <= 0 || ch <= 0) return;
    UIFont *f = [UIFont systemFontOfSize:_fs * cw weight:UIFontWeightBold];
    CGSize ts = [_text sizeWithAttributes:@{ NSFontAttributeName: f }];
    ts = CGSizeMake(ceil(ts.width), ceil(ts.height));
    _label.font = f;
    _label.text = _text;
    _label.textColor = _color;
    self.frame = CGRectMake(_pos.x * cw - kTBPad, _pos.y * ch - kTBPad, ts.width + 2 * kTBPad, ts.height + 2 * kTBPad);
    _label.frame = CGRectMake(kTBPad, kTBPad, ts.width, ts.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _dash.frame = self.bounds;
    _dash.path = [UIBezierPath bezierPathWithRect:CGRectInset(self.bounds, kTBPad - 4, kTBPad - 4)].CGPath;
    [CATransaction commit];
    _del.center = CGPointMake(12, 12);
    _handle.center = CGPointMake(self.bounds.size.width - 13, self.bounds.size.height - 13);
}

- (NSDictionary *)model {
    return @{ @"text": _text ?: @"", @"pos": [NSValue valueWithCGPoint:_pos], @"fs": @(_fs), @"color": _color ?: UIColor.whiteColor };
}

- (void)delTap { if (self.onDelete) self.onDelete(self); }

- (void)tap:(UITapGestureRecognizer *)g {
    if (!_selected) { if (self.onSelect) self.onSelect(self); }
    else if (self.onEdit) self.onEdit(self);   // đang chọn rồi chạm lần nữa = sửa chữ
}

- (void)panSelf:(UIPanGestureRecognizer *)g {
    UIView *sv = self.superview;
    if (!sv) return;
    if (g.state == UIGestureRecognizerStateBegan && self.onSelect) self.onSelect(self);
    CGPoint t = [g translationInView:sv];
    [g setTranslation:CGPointZero inView:sv];
    CGFloat cw = _canvasSize.width, ch = _canvasSize.height;
    if (cw <= 0 || ch <= 0) return;
    _pos.x = MIN(MAX(_pos.x + t.x / cw, 0), 0.97);
    _pos.y = MIN(MAX(_pos.y + t.y / ch, 0), 0.97);
    [self relayout];
}

- (void)pinch:(UIPinchGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        _startFs = _fs;
        if (self.onSelect) self.onSelect(self);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        [self setFsClamped:_startFs * g.scale];
        [self relayout];
    }
}

- (void)panHandle:(UIPanGestureRecognizer *)g {
    UIView *sv = self.superview;
    if (!sv) return;
    CGPoint p = [g locationInView:sv];
    CGPoint o = CGPointMake(_pos.x * _canvasSize.width, _pos.y * _canvasSize.height);
    CGFloat d = MAX(hypot(p.x - o.x, p.y - o.y), 1);
    if (g.state == UIGestureRecognizerStateBegan) {
        _startFs = _fs;
        _startDist = d;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        [self setFsClamped:_startFs * d / _startDist];
        [self relayout];
    }
}
@end

#pragma mark - Dịch ảnh sang tiếng Việt (OCR Vision + dịch online)

@interface STLine : NSObject
@property (nonatomic) CGRect rect, lastRect;       // toạ độ điểm trong ảnh, gốc trên-trái
@property (nonatomic) NSInteger lineCount;
@property (nonatomic, copy) NSString *text, *vi;
@end
@implementation STLine
@end

// gộp các dòng liền kề, cùng cỡ chữ, thẳng hàng thành một đoạn để dịch cho đúng nghĩa
static NSArray<STLine *> *STGroupLines(NSArray<STLine *> *lines) {
    NSArray<STLine *> *sorted = [lines sortedArrayUsingComparator:^NSComparisonResult(STLine *a, STLine *b) {
        if (a.rect.origin.y < b.rect.origin.y) return NSOrderedAscending;
        if (a.rect.origin.y > b.rect.origin.y) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSMutableArray<STLine *> *groups = [NSMutableArray array];
    for (STLine *l in sorted) {
        STLine *target = nil;
        CGFloat h = l.rect.size.height;
        for (STLine *g in groups.reverseObjectEnumerator) {
            if (g.lineCount >= 12) continue;
            CGFloat gap = l.rect.origin.y - CGRectGetMaxY(g.lastRect);
            CGFloat ratio = h / MAX(g.lastRect.size.height, 1);
            if (gap < -0.4 * h || gap > 0.6 * h) continue;
            if (ratio < 0.7 || ratio > 1.4) continue;
            BOOL left = fabs(l.rect.origin.x - g.lastRect.origin.x) < 1.2 * h;
            BOOL center = fabs(CGRectGetMidX(l.rect) - CGRectGetMidX(g.lastRect)) < 1.2 * h;
            if (!(left || center)) continue;
            target = g;
            break;
        }
        if (target) {
            target.text = [target.text stringByAppendingFormat:@" %@", l.text];
            target.rect = CGRectUnion(target.rect, l.rect);
            target.lastRect = l.rect;
            target.lineCount += 1;
        } else {
            STLine *g = [STLine new];
            g.text = l.text;
            g.rect = g.lastRect = l.rect;
            g.lineCount = 1;
            [groups addObject:g];
        }
    }
    return groups;
}

static inline void STPixel(const uint8_t *b, size_t pw, size_t ph, NSInteger x, NSInteger y, int *r, int *g, int *bl) {
    x = MIN(MAX(x, 0), (NSInteger)pw - 1);
    y = MIN(MAX(y, 0), (NSInteger)ph - 1);
    const uint8_t *p = b + ((size_t)y * pw + (size_t)x) * 4;
    *r = p[0]; *g = p[1]; *bl = p[2];
}

static inline double STLum(int r, int g, int b) { return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0; }

// màu nền = màu xuất hiện nhiều nhất ở viền quanh khối chữ
static void STSampleBG(const uint8_t *buf, size_t pw, size_t ph, CGRect pr, int *R, int *G, int *B) {
    int *cnt = calloc(4096, sizeof(int));
    long *sum = calloc(4096 * 3, sizeof(long));
    NSInteger x0 = (NSInteger)floor(pr.origin.x) - 3, x1 = (NSInteger)ceil(CGRectGetMaxX(pr)) + 3;
    NSInteger y0 = (NSInteger)floor(pr.origin.y) - 3, y1 = (NSInteger)ceil(CGRectGetMaxY(pr)) + 3;
    void (^add)(NSInteger, NSInteger) = ^(NSInteger x, NSInteger y) {
        int r, g, b;
        STPixel(buf, pw, ph, x, y, &r, &g, &b);
        int k = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
        cnt[k]++;
        sum[k * 3] += r; sum[k * 3 + 1] += g; sum[k * 3 + 2] += b;
    };
    for (NSInteger x = x0; x <= x1; x += 3) { add(x, y0); add(x, y1); }
    for (NSInteger y = y0; y <= y1; y += 3) { add(x0, y); add(x1, y); }
    int best = 0;
    for (int k = 1; k < 4096; k++) if (cnt[k] > cnt[best]) best = k;
    int c = MAX(cnt[best], 1);
    *R = (int)(sum[best * 3] / c); *G = (int)(sum[best * 3 + 1] / c); *B = (int)(sum[best * 3 + 2] / c);
    free(cnt);
    free(sum);
}

static UIImage *STCompose(UIImage *img, NSArray<STLine *> *blocks) {
    CGImageRef cg = img.CGImage;
    size_t pw = CGImageGetWidth(cg), ph = CGImageGetHeight(cg);
    if (pw == 0 || ph == 0 || img.size.width <= 0) return nil;
    NSMutableData *buf = [NSMutableData dataWithLength:pw * ph * 4];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(buf.mutableBytes, pw, ph, 8, pw * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!c) return nil;
    CGContextDrawImage(c, CGRectMake(0, 0, pw, ph), cg);
    CGContextRelease(c);
    const uint8_t *px = buf.bytes;
    CGFloat sc = (CGFloat)pw / img.size.width;

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = img.scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:img.size format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, img.size.width, img.size.height)];
        for (STLine *b in blocks) {
            if (b.vi.length == 0) continue;
            CGRect rect = CGRectInset(b.rect, -2, -2);
            CGRect pr = CGRectMake(rect.origin.x * sc, rect.origin.y * sc, rect.size.width * sc, rect.size.height * sc);
            int R, G, B;
            STSampleBG(px, pw, ph, pr, &R, &G, &B);

            // màu chữ gốc: trung bình các điểm lệch nhiều so với nền; không đủ tương phản thì dùng đen/trắng
            long fr = 0, fg = 0, fb = 0, n = 0;
            for (NSInteger y = (NSInteger)pr.origin.y; y < (NSInteger)CGRectGetMaxY(pr); y += 2) {
                for (NSInteger x = (NSInteger)pr.origin.x; x < (NSInteger)CGRectGetMaxX(pr); x += 2) {
                    int pr_, pg, pb;
                    STPixel(px, pw, ph, x, y, &pr_, &pg, &pb);
                    if (abs(pr_ - R) + abs(pg - G) + abs(pb - B) > 150) { fr += pr_; fg += pg; fb += pb; n++; }
                }
            }
            UIColor *fgc;
            double bgL = STLum(R, G, B);
            if (n >= 6 && fabs(STLum((int)(fr / n), (int)(fg / n), (int)(fb / n)) - bgL) > 0.3) {
                fgc = [UIColor colorWithRed:fr / n / 255.0 green:fg / n / 255.0 blue:fb / n / 255.0 alpha:1];
            } else {
                fgc = bgL > 0.55 ? [UIColor colorWithWhite:0.08 alpha:1] : UIColor.whiteColor;
            }

            [[UIColor colorWithRed:R / 255.0 green:G / 255.0 blue:B / 255.0 alpha:1] setFill];
            UIRectFill(rect);

            CGFloat lineH = b.rect.size.height / MAX(b.lineCount, 1);
            CGFloat maxF = MIN(MAX(lineH * 0.95, 9), 64);
            NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
            ps.lineBreakMode = NSLineBreakByWordWrapping;
            CGFloat fs = maxF, textH = 0;
            NSDictionary *attrs = nil;
            for (; fs >= 6; fs -= 0.5) {
                attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:fs weight:UIFontWeightMedium],
                           NSForegroundColorAttributeName: fgc, NSParagraphStyleAttributeName: ps };
                CGRect tb = [b.vi boundingRectWithSize:CGSizeMake(rect.size.width, CGFLOAT_MAX)
                                               options:NSStringDrawingUsesLineFragmentOrigin attributes:attrs context:nil];
                textH = ceil(tb.size.height);
                if (textH <= rect.size.height + 1) break;
            }
            CGRect dr = CGRectMake(rect.origin.x, rect.origin.y + MAX((rect.size.height - textH) / 2, 0), rect.size.width, textH);
            [b.vi drawInRect:dr withAttributes:attrs];
        }
    }];
}

static NSString *STTranslateOne(NSString *text, NSString **srcLang) {
    NSURL *url = [NSURL URLWithString:@"https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=vi&dt=t"];
    NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    rq.HTTPMethod = @"POST";
    [rq setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    NSMutableCharacterSet *ok = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [ok removeCharactersInString:@"&+=?/;:#$,@"];
    NSString *enc = [text stringByAddingPercentEncodingWithAllowedCharacters:ok];
    rq.HTTPBody = [[NSString stringWithFormat:@"q=%@", enc] dataUsingEncoding:NSUTF8StringEncoding];

    __block NSString *out = nil;
    __block NSString *lang = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[NSURLSession.sharedSession dataTaskWithRequest:rq completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (!err && data && code == 200) {
            id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([j isKindOfClass:NSArray.class] && [(NSArray *)j count] > 0 && [j[0] isKindOfClass:NSArray.class]) {
                NSMutableString *m = [NSMutableString string];
                for (id seg in (NSArray *)j[0]) {
                    if ([seg isKindOfClass:NSArray.class] && [(NSArray *)seg count] > 0 && [seg[0] isKindOfClass:NSString.class]) [m appendString:seg[0]];
                }
                if (m.length) out = [m copy];
                if ([(NSArray *)j count] > 2 && [j[2] isKindOfClass:NSString.class]) lang = j[2];
            }
        }
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    if (srcLang) *srcLang = lang;
    return out;
}

// Chạy ở nền. progress/completion có thể được gọi từ thread bất kỳ.
static void STTranslateImage(UIImage *img, void (^progress)(NSString *), void (^completion)(UIImage *, NSString *)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CGImageRef cg = img.CGImage;
        if (!cg) { completion(nil, @"Không đọc được ảnh"); return; }

        VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:nil];
        req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        req.usesLanguageCorrection = YES;
        if ([req respondsToSelector:NSSelectorFromString(@"setAutomaticallyDetectsLanguage:")]) {
            [req setValue:@YES forKey:@"automaticallyDetectsLanguage"];   // iOS 16+: tự nhận ngôn ngữ (Anh, Trung, Nhật, Hàn...)
        }
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        NSError *err = nil;
        if (![h performRequests:@[req] error:&err]) { completion(nil, @"Không nhận dạng được chữ"); return; }

        NSMutableArray<STLine *> *lines = [NSMutableArray array];
        CGSize sz = img.size;
        for (id obj in req.results) {
            if (![obj isKindOfClass:VNRecognizedTextObservation.class]) continue;
            VNRecognizedTextObservation *o = obj;
            VNRecognizedText *top = [o topCandidates:1].firstObject;
            if (!top || top.confidence < 0.3) continue;
            NSString *t = [top.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (t.length < 2) continue;
            if ([t rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) continue;   // chỉ số / ký hiệu
            CGRect bb = o.boundingBox;   // chuẩn hoá, gốc dưới-trái
            STLine *l = [STLine new];
            l.text = t;
            l.rect = CGRectMake(bb.origin.x * sz.width, (1 - bb.origin.y - bb.size.height) * sz.height,
                                bb.size.width * sz.width, bb.size.height * sz.height);
            [lines addObject:l];
        }
        if (lines.count == 0) { completion(nil, @"Không thấy chữ nào trong ảnh"); return; }

        NSArray<STLine *> *blocks = STGroupLines(lines);
        if (blocks.count > 60) blocks = [blocks subarrayWithRange:NSMakeRange(0, 60)];
        progress([NSString stringWithFormat:@"Đang dịch %lu đoạn…", (unsigned long)blocks.count]);

        dispatch_group_t grp = dispatch_group_create();
        dispatch_semaphore_t slots = dispatch_semaphore_create(5);
        dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        __block int okCount = 0;
        NSObject *lock = [NSObject new];
        for (STLine *b in blocks) {
            dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
            dispatch_group_async(grp, q, ^{
                NSString *lang = nil;
                NSString *vi = STTranslateOne(b.text, &lang);
                if (vi) {
                    @synchronized (lock) { okCount++; }
                    BOOL same = [lang hasPrefix:@"vi"] ||
                        [[vi stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] caseInsensitiveCompare:b.text] == NSOrderedSame;
                    if (!same) b.vi = vi;
                }
                dispatch_semaphore_signal(slots);
            });
        }
        dispatch_group_wait(grp, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)));

        if (okCount == 0) { completion(nil, @"Không dịch được, kiểm tra kết nối mạng"); return; }
        BOOL any = NO;
        for (STLine *b in blocks) if (b.vi.length) { any = YES; break; }
        if (!any) { completion(nil, @"Ảnh đã là tiếng Việt hoặc không cần dịch"); return; }
        UIImage *out = STCompose(img, blocks);
        completion(out, out ? nil : @"Không tạo được ảnh đã dịch");
    });
}

#pragma mark - Editor

@interface STEditView : UIView <UITextFieldDelegate>
@property (nonatomic, copy) void (^onDone)(UIImage *result); // nil = hủy
- (instancetype)initWithImage:(UIImage *)image frame:(CGRect)frame;
@end

@implementation STEditView {
    UIImage *_image, *_origImage, *_transImage;
    UIView *_content;
    UIImageView *_iv;
    STCanvas *_canvas;
    STPassView *_textLayer;
    NSMutableArray<STTextBox *> *_boxes;
    NSMutableArray *_actions;          // lịch sử để undo: @"s" = nét vẽ, STTextBox = chữ
    STTextBox *_selected, *_editingBox;
    UIButton *_cancelBtn, *_shareBtn, *_undoBtn, *_sizeBtn, *_trBtn;
    UILabel *_status;
    NSArray<UIButton *> *_colorBtns, *_toolBtns;
    NSArray<UIColor *> *_colors;
    NSInteger _colorIdx, _sizeIdx, _trGen, _statusGen;
    STTool _tool;
    UITextField *_field;
    UIWindow *_prevKey;
    BOOL _finished, _translating, _translated;
}

- (instancetype)initWithImage:(UIImage *)image frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _image = _origImage = image;
    _boxes = [NSMutableArray array];
    _actions = [NSMutableArray array];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];

    _content = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:_content];
    _iv = [[UIImageView alloc] initWithImage:image];
    [_content addSubview:_iv];
    _canvas = [[STCanvas alloc] initWithFrame:CGRectZero];
    __weak typeof(self) ws = self;
    _canvas.onTextTap = ^(CGPoint p) { [ws textTapAt:p]; };
    _canvas.onBackgroundTouch = ^BOOL { return [ws backgroundTouch]; };
    _canvas.onStrokeDone = ^{ [ws strokeDone]; };
    [_content addSubview:_canvas];
    _textLayer = [[STPassView alloc] initWithFrame:CGRectZero];
    [_content addSubview:_textLayer];

    UIColor *dark = [UIColor colorWithWhite:1 alpha:0.18];
    _cancelBtn = STRoundButton(@"xmark", dark, 40);
    [_cancelBtn addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    _shareBtn = STRoundButton(@"checkmark", [UIColor colorWithRed:0.18 green:0.7 blue:0.35 alpha:1], 40);
    [_shareBtn addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
    _trBtn = STRoundButtonAny(@[@"translate", @"character.bubble", @"globe"], dark, 40);
    [_trBtn addTarget:self action:@selector(translateTap) forControlEvents:UIControlEventTouchUpInside];
    _undoBtn = STRoundButton(@"arrow.uturn.backward", dark, 36);
    [_undoBtn addTarget:self action:@selector(undoTap) forControlEvents:UIControlEventTouchUpInside];
    _sizeBtn = STRoundButton(nil, dark, 36);
    _sizeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [_sizeBtn addTarget:self action:@selector(cycleSize) forControlEvents:UIControlEventTouchUpInside];

    _status = [UILabel new];
    _status.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _status.textColor = UIColor.whiteColor;
    _status.textAlignment = NSTextAlignmentCenter;
    _status.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    _status.layer.cornerRadius = 14;
    _status.clipsToBounds = YES;
    _status.hidden = YES;

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
    for (UIView *v in @[_cancelBtn, _trBtn, _shareBtn, _undoBtn, _sizeBtn, _status]) [self addSubview:v];

    _colorIdx = 0;
    _sizeIdx = 1;
    _tool = STToolPen;
    [self applyTool];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(kbChange:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)strokeDone { [_actions addObject:@"s"]; }

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
- (void)pickColor:(UIButton *)b {
    _colorIdx = b.tag;
    [self applyTool];
    if (_selected && !_field) { _selected.color = _colors[_colorIdx]; [_selected relayout]; }   // đang chọn chữ -> đổi màu chữ đó
}
- (void)pickTool:(UIButton *)b { [self commitText]; _tool = (STTool)b.tag; [self applyTool]; }
- (void)cycleSize {
    [self commitText];
    _sizeIdx = (_sizeIdx + 1) % 3;
    [self applyTool];
    CGFloat cw = _canvas.bounds.size.width;
    if (_selected && cw > 0) { _selected.fs = _canvas.fontPt / cw; [_selected relayout]; }   // đang chọn chữ -> đổi cỡ chữ đó
}

- (void)undoTap {
    [self commitText];
    while (_actions.count) {
        id a = _actions.lastObject;
        [_actions removeLastObject];
        if ([a isKindOfClass:NSString.class]) { [_canvas undo]; return; }
        STTextBox *b = a;
        if (b.superview) { [self removeBox:b]; return; }   // chữ đã bị xoá tay thì bỏ qua
    }
}

#pragma mark text

- (BOOL)backgroundTouch {
    if (_field) { [self commitText]; return YES; }
    if (_selected) { _selected.selected = NO; _selected = nil; return YES; }
    return NO;
}

- (void)selectBox:(STTextBox *)b {
    if (_field && _editingBox != b) [self commitText];
    if (_selected == b) return;
    _selected.selected = NO;
    _selected = b;
    b.selected = YES;
    [_textLayer bringSubviewToFront:b];
}

- (void)removeBox:(STTextBox *)b {
    if (b == _selected) _selected = nil;
    if (b == _editingBox) _editingBox = nil;
    [b removeFromSuperview];
    [_boxes removeObject:b];
}

- (STTextBox *)newBoxWithText:(NSString *)t pos:(CGPoint)pos fs:(CGFloat)fs color:(UIColor *)c {
    STTextBox *b = [STTextBox new];
    b.text = t;
    b.color = c ?: UIColor.whiteColor;
    b.fs = fs;
    b.pos = pos;
    b.canvasSize = _canvas.bounds.size;
    __weak typeof(self) ws = self;
    b.onSelect = ^(STTextBox *x) { [ws selectBox:x]; };
    b.onEdit = ^(STTextBox *x) { [ws editBox:x]; };
    b.onDelete = ^(STTextBox *x) { [ws removeBox:x]; };
    [_textLayer addSubview:b];
    [_boxes addObject:b];
    [b relayout];
    return b;
}

- (void)textTapAt:(CGPoint)pc {
    if (_field) { [self commitText]; return; }
    [self beginEditBox:nil at:pc];
}

- (void)editBox:(STTextBox *)b {
    if (_field) [self commitText];
    [self beginEditBox:b at:CGPointZero];
}

- (void)beginEditBox:(STTextBox *)box at:(CGPoint)pc {
    CGSize cs = _canvas.bounds.size;
    if (cs.width <= 0 || cs.height <= 0) return;
    CGFloat fpt = box ? box.fs * cs.width : _canvas.fontPt;
    UIFont *font = [UIFont systemFontOfSize:fpt weight:UIFontWeightBold];
    CGFloat fh = ceil(fpt * 1.5);
    CGFloat x, y;
    if (box) {
        x = box.pos.x * cs.width;
        y = box.pos.y * cs.height - (fh - font.lineHeight) / 2;   // chữ giữ nguyên vị trí khi sửa
    } else {
        x = MIN(MAX(pc.x, 0), MAX(cs.width - 80, 0));
        y = MIN(MAX(pc.y - fh / 2, 0), MAX(cs.height - fh, 0));
    }
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(x, y, MAX(cs.width - x, 80), fh)];
    tf.font = font;
    UIColor *c = box ? box.color : _colors[_colorIdx];
    tf.textColor = c;
    tf.tintColor = c;
    tf.text = box ? box.text : nil;
    tf.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    tf.borderStyle = UITextBorderStyleNone;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = self;
    [_canvas addSubview:tf];
    _field = tf;
    _editingBox = box;
    box.hidden = YES;

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
    STTextBox *eb = _editingBox;
    _editingBox = nil;
    NSString *t = tf.text ?: @"";
    BOOL empty = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0;
    CGSize cs = _canvas.bounds.size;
    if (eb) {
        eb.hidden = NO;
        if (empty) [self removeBox:eb];                    // sửa thành rỗng = xoá chữ
        else { eb.text = t; eb.color = tf.textColor ?: UIColor.whiteColor; [eb relayout]; }
    } else if (!empty && cs.width > 0 && cs.height > 0) {
        UIFont *font = tf.font;
        CGFloat lh = font.lineHeight;
        CGPoint pos = CGPointMake(tf.frame.origin.x / cs.width, (tf.frame.origin.y + (tf.frame.size.height - lh) / 2) / cs.height);
        STTextBox *b = [self newBoxWithText:t pos:pos fs:font.pointSize / cs.width color:tf.textColor];
        [_actions addObject:b];
        [self selectBox:b];                                // chọn luôn để kéo / đổi cỡ được ngay
    }
    [tf resignFirstResponder];
    [tf removeFromSuperview];
    [_prevKey makeKeyWindow];
    _prevKey = nil;
    [UIView animateWithDuration:0.25 animations:^{ self->_content.transform = CGAffineTransformIdentity; }];
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

#pragma mark dịch

- (void)setBaseImage:(UIImage *)img {
    _image = img;
    _iv.image = img;
}

- (void)updateTrBtn {
    _trBtn.backgroundColor = _translated ? [UIColor colorWithRed:0.2 green:0.5 blue:1 alpha:1] : [UIColor colorWithWhite:1 alpha:0.18];
}

- (void)showStatus:(NSString *)msg autoHide:(BOOL)hide {
    _status.text = msg;
    _status.hidden = NO;
    [self setNeedsLayout];
    NSInteger g = ++_statusGen;
    if (hide) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (g == self->_statusGen) self->_status.hidden = YES;
        });
    }
}

- (void)translateTap {
    if (_translating) return;
    [self commitText];
    if (_translated) {                       // đang xem bản dịch -> quay về ảnh gốc
        [self setBaseImage:_origImage];
        _translated = NO;
        [self updateTrBtn];
        return;
    }
    if (_transImage) {                       // đã dịch rồi -> bật lại bản dịch
        [self setBaseImage:_transImage];
        _translated = YES;
        [self updateTrBtn];
        return;
    }
    _translating = YES;
    NSInteger gen = ++_trGen;
    [self showStatus:@"Đang nhận dạng chữ…" autoHide:NO];
    __weak typeof(self) ws = self;
    STTranslateImage(_origImage,
        ^(NSString *msg) {
            dispatch_async(dispatch_get_main_queue(), ^{
                STEditView *s = ws;
                if (s && s->_trGen == gen) [s showStatus:msg autoHide:NO];
            });
        },
        ^(UIImage *out, NSString *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                STEditView *s = ws;
                if (!s || s->_trGen != gen) return;
                s->_translating = NO;
                if (!out) { [s showStatus:err ?: @"Không dịch được" autoHide:YES]; return; }
                s->_transImage = out;
                [s setBaseImage:out];
                s->_translated = YES;
                [s updateTrBtn];
                s->_status.hidden = YES;
            });
        });
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
    _trBtn.center = CGPointMake(W / 2, s.top + 32);
    CGSize ss = [_status sizeThatFits:CGSizeMake(W - 40, 28)];
    _status.bounds = CGRectMake(0, 0, MIN(ss.width + 28, W - 24), 28);
    _status.center = CGPointMake(W / 2, s.top + 32 + 44);

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
    _textLayer.frame = r;
    for (STTextBox *b in _boxes) { b.canvasSize = r.size; [b relayout]; }
    [_canvas setNeedsDisplay];
}

- (UIImage *)render {
    if (_canvas.strokes.count == 0 && _boxes.count == 0) return _image;
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat];
    f.scale = _image.scale;
    CGSize size = _image.size;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:f];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [self->_image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        STDrawStrokes(self->_canvas.strokes, size);
        for (STTextBox *b in self->_boxes) {
            NSDictionary *m = b.model;
            STDrawText(m[@"text"], [m[@"pos"] CGPointValue], [m[@"fs"] doubleValue], m[@"color"], size);
        }
    }];
}

- (void)finish {
    if (_finished) return;
    [self commitText];
    _finished = YES;
    _trGen++;
    if (self.onDone) self.onDone([self render]);
}
- (void)cancel {
    if (_finished) return;
    [self commitText];
    _finished = YES;
    _trGen++;
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
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressButton:)];
    lp.minimumPressDuration = 0.5;
    lp.allowableMovement = 8;
    [_button addGestureRecognizer:lp];   // giữ nút = chụp toàn màn hình ngay
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

- (void)longPressButton:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || _snip || _edit) return;
    UIImage *shot = [self captureScene];
    if (!shot) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    _button.hidden = YES;
    [self openEditorWithImage:shot];
}

- (void)restoreButton {
    _button.hidden = _userHidden;
    [self layoutButton];
}

- (void)openEditorWithImage:(UIImage *)img {
    STEditView *e = [[STEditView alloc] initWithImage:img frame:_root.view.bounds];
    __weak typeof(self) ws = self;
    e.onDone = ^(UIImage *result) { [ws finishEditWithImage:result]; };
    [_root.view addSubview:e];
    _edit = e;
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

    [self openEditorWithImage:out];
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
