//
//  XWDragCellCollectionView.m
//  PanCollectionView
//
//  Created by YouLoft_MacMini on 16/1/4.
//  Copyright © 2016年 wazrx. All rights reserved.
//

#import "XWDragCellCollectionView.h"
#import <AudioToolbox/AudioToolbox.h>

#define angelToRandian(x)  ((x)/180.0*M_PI)


typedef NS_ENUM(NSUInteger, XWDragCellCollectionViewScrollDirection) {
    XWDragCellCollectionViewScrollDirectionNone = 0,
    XWDragCellCollectionViewScrollDirectionLeft,
    XWDragCellCollectionViewScrollDirectionRight,
    XWDragCellCollectionViewScrollDirectionUp,
    XWDragCellCollectionViewScrollDirectionDown
};

@interface XWDragCellCollectionView ()
@property (nonatomic, strong) NSIndexPath *originalIndexPath;
@property (nonatomic, strong) NSIndexPath *moveIndexPath;
@property (nonatomic, weak) UIView *tempMoveCell;
@property (nonatomic, weak) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) CADisplayLink *edgeTimer;
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, assign) XWDragCellCollectionViewScrollDirection scrollDirection;
@property (nonatomic, assign) CGFloat oldMinimumPressDuration;
@property (nonatomic, assign, getter=isObservering) BOOL observering;

@end

@implementation XWDragCellCollectionView

@dynamic delegate;
@dynamic dataSource;

- (void)dealloc{
    [self removeObserver:self forKeyPath:@"contentOffset"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - initailize methods

- (instancetype)initWithFrame:(CGRect)frame collectionViewLayout:(nonnull UICollectionViewLayout *)layout
{
    self = [super initWithFrame:frame collectionViewLayout:layout];
    if (self) {
        [self xwp_initializeProperty];
        [self xwp_addGesture];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self xwp_initializeProperty];
        [self xwp_addGesture];
    }
    return self;
}

- (void)xwp_initializeProperty{
    _minimumPressDuration = 1;
    _edgeScrollEable = YES;
    _shakeWhenMoveing = YES;
    _shakeLevel = 4.0f;
    
    [self addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
}

#pragma mark - longPressGesture methods

/**
 *  添加一个自定义的滑动手势
 */
- (void)xwp_addGesture{
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(xwp_longPressed:)];
    _longPressGesture = longPress;
    longPress.minimumPressDuration = _minimumPressDuration;
    [self addGestureRecognizer:longPress];
}

/**
 *  监听手势的改变
 */
- (void)xwp_longPressed:(UILongPressGestureRecognizer *)longPressGesture{
    if (longPressGesture.state == UIGestureRecognizerStateBegan) {
        [self xwp_gestureBegan:longPressGesture];
    }
    if (longPressGesture.state == UIGestureRecognizerStateChanged) {
        [self xwp_gestureChange:longPressGesture];
    }
    if (longPressGesture.state == UIGestureRecognizerStateCancelled ||
        longPressGesture.state == UIGestureRecognizerStateEnded || longPressGesture.state == UIGestureRecognizerStateFailed){
        [self xwp_gestureEndOrCancle:longPressGesture];
    }
}

/**
 *  手势开始
 */
- (void)xwp_gestureBegan:(UILongPressGestureRecognizer *)longPressGesture{
    NSIndexPath *indexPath = [self indexPathForItemAtPoint:[longPressGesture locationOfTouch:0 inView:longPressGesture.view]];
    
    if ([self.delegate respondsToSelector:@selector(collectionView:cellCanDragAtIndexPath:)]) {
        if (![self.delegate collectionView:self cellCanDragAtIndexPath:indexPath]) {
            return;
        }
    }
    //获取手指所在的cell
    _originalIndexPath = indexPath;
    
    UICollectionViewCell *cell = [self cellForItemAtIndexPath:_originalIndexPath];
    UIView *tempMoveCell = [cell snapshotViewAfterScreenUpdates:NO];
    cell.hidden = YES;
    _tempMoveCell = tempMoveCell;
    _tempMoveCell.frame = cell.frame;
    [self addSubview:_tempMoveCell];
    tempMoveCell.transform = CGAffineTransformMakeScale(1.2,1.2);
    //开启边缘滚动定时器
    [self xwp_setEdgeTimer];
    //开启抖动
    if (_shakeWhenMoveing && !_editing) {
        [self xw_enterEditingModel];
        //        [self xwp_shakeAllCell];
        //        [self addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
    }
    _lastPoint = [longPressGesture locationOfTouch:0 inView:longPressGesture.view];
    //通知代理
    if ([self.delegate respondsToSelector:@selector(dragCellCollectionView:cellWillBeginMoveAtIndexPath:)]) {
        [self.delegate dragCellCollectionView:self cellWillBeginMoveAtIndexPath:_originalIndexPath];
    }
}
/**
 *  手势拖动
 */
- (void)xwp_gestureChange:(UILongPressGestureRecognizer *)longPressGesture{
    //通知代理
    if ([self.delegate respondsToSelector:@selector(dragCellCollectionViewCellisMoving:)]) {
        [self.delegate dragCellCollectionViewCellisMoving:self];
    }
    CGFloat tranX = [longPressGesture locationOfTouch:0 inView:longPressGesture.view].x - _lastPoint.x;
    CGFloat tranY = [longPressGesture locationOfTouch:0 inView:longPressGesture.view].y - _lastPoint.y;
    _tempMoveCell.center = CGPointApplyAffineTransform(_tempMoveCell.center, CGAffineTransformMakeTranslation(tranX, tranY));
    _lastPoint = [longPressGesture locationOfTouch:0 inView:longPressGesture.view];
    [self xwp_moveCell];
}

/**
 *  手势取消或者结束
 */
- (void)xwp_gestureEndOrCancle:(UILongPressGestureRecognizer *)longPressGesture{
    UICollectionViewCell *cell = [self cellForItemAtIndexPath:_originalIndexPath];
    self.userInteractionEnabled = NO;
    [self xwp_stopEdgeTimer];
    //通知代理
    if ([self.delegate respondsToSelector:@selector(dragCellCollectionViewCellEndMoving:)]) {
        [self.delegate dragCellCollectionViewCellEndMoving:self];
    }
    [UIView animateWithDuration:0.25 animations:^{
        _tempMoveCell.center = cell.center;
        _tempMoveCell.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        //        [self xwp_stopShakeAllCell];
        [_tempMoveCell removeFromSuperview];
        cell.hidden = NO;
        self.userInteractionEnabled = YES;
    }];
}

#pragma mark - setter methods

- (void)setMinimumPressDuration:(NSTimeInterval)minimumPressDuration{
    _minimumPressDuration = minimumPressDuration;
    _longPressGesture.minimumPressDuration = minimumPressDuration;
}

- (void)setShakeLevel:(CGFloat)shakeLevel{
    CGFloat level = MAX(1.0f, shakeLevel);
    _shakeLevel = MIN(level, 10.0f);
}

#pragma mark - timer methods

- (void)xwp_setEdgeTimer{
    if (!_edgeTimer && _edgeScrollEable) {
        _edgeTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(xwp_edgeScroll)];
        [_edgeTimer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)xwp_stopEdgeTimer{
    if (_edgeTimer) {
        [_edgeTimer invalidate];
        _edgeTimer = nil;
    }
}

#pragma mark - private methods
/**
 *	@brief 判断当前cell是否可移动
 */
-(BOOL)xwp_judgeCellMove:(NSIndexPath *)indexPath
{
    BOOL isMoving = YES;
    
    if ([self.delegate respondsToSelector:@selector(collectionView:canMoveItemAtIndexPath:)]) {
        return [self.delegate collectionView:self cellCanMoveAtIndexPath:indexPath];
    }
    
    NSMutableArray *temp = @[].mutableCopy;
    //获取数据源
    if ([self.dataSource respondsToSelector:@selector(dataSourceArrayOfCollectionView:)]) {
        [temp addObjectsFromArray:[self.dataSource dataSourceArrayOfCollectionView:self]];
    }
    //判断数据源是单个数组还是数组套数组的多section形式，YES表示数组套数组
    BOOL dataTypeCheck = ([self numberOfSections] != 1 || ([self numberOfSections] == 1 && [temp[0] isKindOfClass:[NSArray class]]));
    if (dataTypeCheck) {
        for (int i = 0; i < temp.count; i ++) {
            [temp replaceObjectAtIndex:i withObject:[temp[i] mutableCopy]];
        }
    }
    if (dataTypeCheck) {
        if (temp.count < (indexPath.section + 1)) {
            isMoving = NO;
        }else{
            NSMutableArray *array = temp[indexPath.section];
            if (array.count < (indexPath.row + 1)) {
                isMoving = NO;
            }
        }
    }else{
        if (temp.count < (indexPath.row + 1)) {
            isMoving = NO;
        }
    }
    
    return isMoving;
}

- (void)xwp_moveCell{
    for (UICollectionViewCell *cell in [self visibleCells]) {
        
        if ([self indexPathForCell:cell] == _originalIndexPath) {
            continue;
        }
        //计算中心距
        CGFloat spacingX = fabs(_tempMoveCell.center.x - cell.center.x);
        CGFloat spacingY = fabs(_tempMoveCell.center.y - cell.center.y);
        if (spacingX <= _tempMoveCell.bounds.size.width / 2.0f && spacingY <= _tempMoveCell.bounds.size.height / 2.0f) {
            NSIndexPath *indexPath = [self indexPathForCell:cell];
            if (![self xwp_judgeCellMove:indexPath]) {
                continue;
            }
            _moveIndexPath = [self indexPathForCell:cell];
            //更新数据源
            [self xwp_updateDataSource];
            //移动
            [self moveItemAtIndexPath:_originalIndexPath toIndexPath:_moveIndexPath];
            //通知代理
            if ([self.delegate respondsToSelector:@selector(dragCellCollectionView:moveCellFromIndexPath:toIndexPath:)]) {
                [self.delegate dragCellCollectionView:self moveCellFromIndexPath:_originalIndexPath toIndexPath:_moveIndexPath];
            }
            //设置移动后的起始indexPath
            _originalIndexPath = _moveIndexPath;
            break;
        }
    }
}

/**
 *  更新数据源
 */
- (void)xwp_updateDataSource{
    NSMutableArray *temp = @[].mutableCopy;
    //获取数据源
    if ([self.dataSource respondsToSelector:@selector(dataSourceArrayOfCollectionView:)]) {
        [temp addObjectsFromArray:[self.dataSource dataSourceArrayOfCollectionView:self]];
    }
    //判断数据源是单个数组还是数组套数组的多section形式，YES表示数组套数组
    BOOL dataTypeCheck = ([self numberOfSections] != 1 || ([self numberOfSections] == 1 && [temp[0] isKindOfClass:[NSArray class]]));
    if (dataTypeCheck) {
        for (int i = 0; i < temp.count; i ++) {
            [temp replaceObjectAtIndex:i withObject:[temp[i] mutableCopy]];
        }
    }
    if (_moveIndexPath.section == _originalIndexPath.section) {
        NSMutableArray *orignalSection = dataTypeCheck ? temp[_originalIndexPath.section] : temp;
        if (_moveIndexPath.item > _originalIndexPath.item) {
            for (NSUInteger i = _originalIndexPath.item; i < _moveIndexPath.item ; i ++) {
                [orignalSection exchangeObjectAtIndex:i withObjectAtIndex:i + 1];
            }
        }else{
            for (NSUInteger i = _originalIndexPath.item; i > _moveIndexPath.item ; i --) {
                [orignalSection exchangeObjectAtIndex:i withObjectAtIndex:i - 1];
            }
        }
    }else{
        NSMutableArray *orignalSection = temp[_originalIndexPath.section];
        NSMutableArray *currentSection = temp[_moveIndexPath.section];
        [currentSection insertObject:orignalSection[_originalIndexPath.item] atIndex:_moveIndexPath.item];
        [orignalSection removeObject:orignalSection[_originalIndexPath.item]];
    }
    //将重排好的数据传递给外部
    if ([self.delegate respondsToSelector:@selector(dragCellCollectionView:newDataArrayAfterMove:)]) {
        [self.delegate dragCellCollectionView:self newDataArrayAfterMove:temp.copy];
    }
}

- (void)xwp_edgeScroll{
    [self xwp_setScrollDirection];
    switch (_scrollDirection) {
        case XWDragCellCollectionViewScrollDirectionLeft:{
            //这里的动画必须设为NO
            [self setContentOffset:CGPointMake(self.contentOffset.x - 4, self.contentOffset.y) animated:NO];
            _tempMoveCell.center = CGPointMake(_tempMoveCell.center.x - 4, _tempMoveCell.center.y);
            _lastPoint.x -= 4;
        }
            break;
        case XWDragCellCollectionViewScrollDirectionRight:{
            [self setContentOffset:CGPointMake(self.contentOffset.x + 4, self.contentOffset.y) animated:NO];
            _tempMoveCell.center = CGPointMake(_tempMoveCell.center.x + 4, _tempMoveCell.center.y);
            _lastPoint.x += 4;
            
        }
            break;
        case XWDragCellCollectionViewScrollDirectionUp:{
            [self setContentOffset:CGPointMake(self.contentOffset.x, self.contentOffset.y - 4) animated:NO];
            _tempMoveCell.center = CGPointMake(_tempMoveCell.center.x, _tempMoveCell.center.y - 4);
            _lastPoint.y -= 4;
        }
            break;
        case XWDragCellCollectionViewScrollDirectionDown:{
            [self setContentOffset:CGPointMake(self.contentOffset.x, self.contentOffset.y + 4) animated:NO];
            _tempMoveCell.center = CGPointMake(_tempMoveCell.center.x, _tempMoveCell.center.y + 4);
            _lastPoint.y += 4;
        }
            break;
        default:
            break;
    }
}

- (void)xwp_shakeAllCell{
    CAKeyframeAnimation* anim=[CAKeyframeAnimation animation];
    anim.keyPath=@"transform.rotation";
    anim.values=@[@(angelToRandian(-_shakeLevel)),@(angelToRandian(_shakeLevel)),@(angelToRandian(-_shakeLevel))];
    anim.repeatCount=MAXFLOAT;
    anim.duration=0.2;
    NSArray *cells = [self visibleCells];
    for (UICollectionViewCell *cell in cells) {
        /**如果加了shake动画就不用再加了*/
        if (![cell.layer animationForKey:@"shake"]) {
            [cell.layer addAnimation:anim forKey:@"shake"];
        }
    }
    if (![_tempMoveCell.layer animationForKey:@"shake"]) {
        [_tempMoveCell.layer addAnimation:anim forKey:@"shake"];
    }
}

- (void)xwp_stopShakeAllCell{
    if (!_shakeWhenMoveing || _editing) {
        return;
    }
    NSArray *cells = [self visibleCells];
    for (UICollectionViewCell *cell in cells) {
        [cell.layer removeAllAnimations];
    }
    if (_tempMoveCell) {
        [_tempMoveCell.layer removeAllAnimations];
    }
    
    //    [self removeObserver:self forKeyPath:@"contentOffset"];
}

- (void)xwp_setScrollDirection{
    _scrollDirection = XWDragCellCollectionViewScrollDirectionNone;
    if (self.bounds.size.height + self.contentOffset.y - _tempMoveCell.center.y < _tempMoveCell.bounds.size.height / 2 && self.bounds.size.height + self.contentOffset.y < self.contentSize.height) {
        _scrollDirection = XWDragCellCollectionViewScrollDirectionDown;
    }
    if (_tempMoveCell.center.y - self.contentOffset.y < _tempMoveCell.bounds.size.height / 2 && self.contentOffset.y > 0) {
        _scrollDirection = XWDragCellCollectionViewScrollDirectionUp;
    }
    if (self.bounds.size.width + self.contentOffset.x - _tempMoveCell.center.x < _tempMoveCell.bounds.size.width / 2 && self.bounds.size.width + self.contentOffset.x < self.contentSize.width) {
        _scrollDirection = XWDragCellCollectionViewScrollDirectionRight;
    }
    
    if (_tempMoveCell.center.x - self.contentOffset.x < _tempMoveCell.bounds.size.width / 2 && self.contentOffset.x > 0) {
        _scrollDirection = XWDragCellCollectionViewScrollDirectionLeft;
    }
}

#pragma mark - public methods

- (void)xw_enterEditingModel{
    if (_isDragSquare && !_editing) {
        _editing = YES;
        _oldMinimumPressDuration =  _longPressGesture.minimumPressDuration;
        _longPressGesture.minimumPressDuration = 0;
        if (_shakeWhenMoveing) {
            [self xwp_shakeAllCell];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(xwp_foreground) name:UIApplicationWillEnterForegroundNotification object:nil];
        }
        if (self.delegate && [self.delegate respondsToSelector:@selector(dragCollectionViewWillBegin:)]) {
            [self.delegate dragCollectionViewWillBegin:self];
        }
    }
}

- (void)xw_stopEditingModel{
    if (_editing) {
        _editing = NO;
        _longPressGesture.minimumPressDuration = _oldMinimumPressDuration;
        [self xwp_stopShakeAllCell];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
        if (self.delegate && [self.delegate respondsToSelector:@selector(dragCollectionViewEnd:)]) {
            [self.delegate dragCollectionViewEnd:self];
        }
    }
}

#pragma mark - overWrite methods

/**
 *  重写hitTest事件，判断是否应该相应自己的滑动手势，还是系统的滑动手势
 */
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    if (_editing) { //切换页面，动画消失，此时须取消九宫格重排
        NSIndexPath *indexPath = [self indexPathForItemAtPoint:point];
        UICollectionViewCell *cell = [self cellForItemAtIndexPath:indexPath];
        if (![cell.layer animationForKey:@"shake"]) {
            [self xw_stopEditingModel];
        }
    }
    _longPressGesture.enabled = (_isDragSquare && ([self indexPathForItemAtPoint:point] && [self xwp_judgeCellMove:[self indexPathForItemAtPoint:point]]));

    
    return [super hitTest:point withEvent:event];
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context{
    if ([keyPath isEqualToString:@"contentOffset"]) {
        if (_observering) {
            return;
        }else{
            _observering = YES;
        }
    }
    [super addObserver:observer forKeyPath:keyPath options:options context:context];
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath{
    if ([keyPath isEqualToString:@"contentOffset"]) {
        if (!_observering) {
            return;
        }else{
            _observering = NO;
        }
    }
    [super removeObserver:observer forKeyPath:keyPath];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context{
    if (_isDragSquare) {
        if (_editing) {
            [self xwp_shakeAllCell];
        }else{
            [self xwp_stopShakeAllCell];
        }
    }
}

#pragma mark - notification

- (void)xwp_foreground{
    if (_editing) {
        [self xwp_shakeAllCell];
    }
}

@end
