# frozen_string_literal: true

require "test_helper"

# ImageData's pixels live in its `data` typed array (host_runtime.js): Dommy
# paints nothing, so they start transparent black, and the page's writes stay
# JS-side rather than crossing the bridge whenever the ImageData does.
class Dommy::Js::TestImageData < Minitest::Test
  def setup
    @h = Dommy::Js::BrowserHarness.new("<canvas id='c'></canvas>")
    @h.execute(<<~JS)
      globalThis.ctx = document.getElementById("c").getContext("2d");
      globalThis.img = ctx.createImageData(2, 3);
    JS
  end

  def teardown
    @h&.dispose
  end

  def test_data_is_one_transparent_black_buffer_per_image_data
    assert_equal(true, @h.evaluate("img.data === img.data && img.data instanceof Uint8ClampedArray"))
    assert_equal(24, @h.evaluate("img.data.length"))
    assert_equal(0, @h.evaluate("img.data.reduce((a, b) => a + b, 0)"))
  end

  # Handing the ImageData to the host keeps what the page wrote.
  def test_writes_survive_the_image_data_crossing_to_the_host
    assert_equal([255, 7], @h.evaluate(<<~JS))
      (() => {
        img.data[0] = 300; img.data[23] = 7;
        ctx.putImageData(img, 0, 0);
        return [img.data[0], img.data[23]];
      })()
    JS
  end

  # A clone carries the pixels written so far and has its own buffer, and a
  # record deserialized twice gives two independent buffers.
  def test_structured_clone_copies_the_pixels
    assert_equal([9, 0, 9, 24], @h.evaluate(<<~JS))
      (() => {
        img.data[5] = 9;
        const copy = structuredClone(img);
        copy.data[6] = 1; img.data[6] = 2;
        const fresh = structuredClone(ctx.createImageData(2, 3));
        return [copy.data[5], fresh.data[5], structuredClone(copy).data[5], copy.data.length];
      })()
    JS
    assert_equal(2, @h.evaluate("structuredClone(img).data[6]"))
  end

  # A clone of an ImageData whose data was never read is transparent black.
  def test_cloning_an_unread_image_data
    assert_equal(24, @h.evaluate("structuredClone(ctx.createImageData(2, 3)).data.length"))
  end
end
