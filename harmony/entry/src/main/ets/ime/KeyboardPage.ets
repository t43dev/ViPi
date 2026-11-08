import { keyboardController, KeyboardView } from './KeyboardController';
import { css } from './Palette';

/**
 * Trang của bảng bàn phím: hai Canvas chồng nhau (lớp phím tĩnh và lớp trên), mọi chạm đi vào Board để tự
 * dò phím theo toạ độ như bản Android (gõ hai ngón, trượt sửa phím, kéo phím cách để dời con trỏ).
 */
@Entry
@Component
struct KeyboardPage {
  private readonly settings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly keys: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private readonly layer: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private keysReady: boolean = false;
  private layerReady: boolean = false;
  @State bg: string = css(keyboardController.board.background);

  aboutToAppear(): void {
    const view: KeyboardView = {
      draw: (staticLayer: boolean, dynamicLayer: boolean): void => this.draw(staticLayer, dynamicLayer)
    };
    keyboardController.attachView(view);
  }

  aboutToDisappear(): void {
    keyboardController.attachView(undefined);
  }

  private draw(staticLayer: boolean, dynamicLayer: boolean): void {
    const board = keyboardController.board;
    if (board.width <= 0) {
      return;
    }
    const bg = css(board.background);
    if (bg !== this.bg) {
      this.bg = bg;
    }
    if (staticLayer && this.keysReady) {
      board.drawStatic(this.keys);
    }
    if (dynamicLayer && this.layerReady) {
      board.drawDynamic(this.layer);
    }
  }

  private handleTouch(event: TouchEvent): void {
    const board = keyboardController.board;
    for (const t of event.changedTouches) {
      switch (t.type) {
        case TouchType.Down:
          board.touchDown(t.id, t.x, t.y);
          break;
        case TouchType.Move:
          board.touchMove(t.id, t.x, t.y);
          break;
        case TouchType.Up:
          board.touchUp(t.id, t.x, t.y);
          break;
        case TouchType.Cancel:
          board.touchCancel();
          break;
        default:
          break;
      }
    }
  }

  build() {
    Stack() {
      Canvas(this.keys)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.keysReady = true;
          this.draw(true, false);
        })
      Canvas(this.layer)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.layerReady = true;
          keyboardController.board.setMeasurer(this.layer);
          this.draw(false, true);
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bg)
    .hitTestBehavior(HitTestMode.Block)
    .onAreaChange((_old: Area, area: Area) => {
      keyboardController.board.resize(Number(area.width), Number(area.height), keyboardController.screenHeight());
      this.draw(true, true);
    })
    .onTouch((event: TouchEvent) => this.handleTouch(event))
  }
}
