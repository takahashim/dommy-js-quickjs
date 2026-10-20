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

  # Handing the ImageData to the host, and reading it back through the host,
  # keeps what the page wrote.
  def test_writes_survive_the_image_data_crossing_to_the_host
    assert_equal([255, 7, true], @h.evaluate(<<~JS))
      (() => {
        img.data[0] = 300; img.data[23] = 7;
        ctx.putImageData(img, 0, 0);
        document.body.held = img;
        const back = document.body.held;
        return [back.data[0], back.data[23], back.data === img.data];
      })()
    JS
  end

  # A clone carries the pixels written so far and has its own buffer.
  def test_structured_clone_copies_the_pixels
    assert_equal([9, 1, 2, 9, 1, 24], @h.evaluate(<<~JS))
      (() => {
        img.data[5] = 9;
        const copy = structuredClone(img);
        copy.data[6] = 1; img.data[6] = 2;
        const again = structuredClone(copy);
        return [copy.data[5], copy.data[6], img.data[6], again.data[5], again.data[6], copy.data.length];
      })()
    JS
    assert_equal(2, @h.evaluate("structuredClone(img).data[6]"))
  end

  # An ImageData sent by message or kept as history state arrives with the
  # pixels written before sending, and the receiver's `data` is one live buffer.
  def test_window_post_message_carries_the_pixels
    @h.execute(<<~JS)
      img.data[0] = 9;
      window.onmessage = (e) => {
        const d = e.data.data;
        d[1] = 5;
        globalThis.got = [d[0], e.data.data[1], d === e.data.data, d === img.data];
      };
      window.postMessage(img, "*");
    JS
    @h.pump
    assert_equal([9, 5, true, false], @h.evaluate("got"))
  end

  def test_message_channel_carries_the_pixels
    @h.execute(<<~JS)
      img.data[0] = 9;
      const { port1, port2 } = new MessageChannel();
      port2.onmessage = (e) => { globalThis.got = [e.data.data[0], e.data.data === e.data.data]; };
      port1.postMessage(img);
    JS
    @h.pump
    assert_equal([9, true], @h.evaluate("got"))
  end

  def test_history_state_carries_the_pixels
    assert_equal([9, true, 0], @h.evaluate(<<~JS))
      (() => {
        img.data[0] = 9;
        history.pushState(img, "");
        img.data[0] = 0;
        const s = history.state;
        return [s.data[0], s.data === history.state.data, img.data[0]];
      })()
    JS
  end

  # The host keeps a delivered ImageData after every proxy of it is gone (the
  # GC runs, and the finalizers with it); what the page wrote through one comes
  # back through the next. An ImageData sent before anything read its `data`
  # has no pixels in the record, and is the receiver's all the same.
  def assert_write_outlives_the_proxies(send, written_before:)
    @h.execute("img.data[0] = 9;") if written_before
    @h.execute(<<~JS)
      globalThis.receive = (e) => { globalThis.kept = e; e.data.data[3] = 7; };
      #{send}
    JS
    @h.pump
    @h.runtime.collect_garbage
    @h.pump
    assert_equal([written_before ? 9 : 0, 7], @h.evaluate("[kept.data.data[0], kept.data.data[3]]"))
  end

  WINDOW_MESSAGE = 'window.onmessage = receive; window.postMessage(img, "*");'
  CHANNEL_MESSAGE = "const c = new MessageChannel(); c.port2.onmessage = receive; c.port1.postMessage(img);"

  def test_a_write_to_an_unread_image_data_sent_by_post_message_outlives_its_proxies
    assert_write_outlives_the_proxies(WINDOW_MESSAGE, written_before: false)
  end

  def test_a_write_to_a_written_image_data_sent_by_post_message_outlives_its_proxies
    assert_write_outlives_the_proxies(WINDOW_MESSAGE, written_before: true)
  end

  def test_a_write_to_an_unread_image_data_sent_through_a_channel_outlives_its_proxies
    assert_write_outlives_the_proxies(CHANNEL_MESSAGE, written_before: false)
  end

  def test_a_write_to_a_written_image_data_sent_through_a_channel_outlives_its_proxies
    assert_write_outlives_the_proxies(CHANNEL_MESSAGE, written_before: true)
  end

  # An ImageData the page hands the host as a value it keeps (a MessageEvent's
  # data) keeps what the page wrote, before handing it over and after, once
  # its proxies are gone.
  def test_an_image_data_the_host_keeps_keeps_its_pixels
    @h.execute(<<~JS)
      img.data[0] = 9;
      globalThis.ev = new MessageEvent("m", { data: img });
      img.data[3] = 7;
      ctx.putImageData(img, 0, 0);
      globalThis.img = null;
    JS
    @h.pump
    @h.runtime.collect_garbage
    @h.pump
    assert_equal([9, 7], @h.evaluate("[ev.data.data[0], ev.data.data[3]]"))
  end

  # One record deserialized for two receivers gives each its own ImageData and
  # pixels, and each keeps its write.
  def test_a_broadcast_gives_each_receiver_its_own_pixels
    @h.execute(<<~JS)
      img.data[0] = 9;
      globalThis.got = [];
      const a = new BroadcastChannel("px"), b = new BroadcastChannel("px"), sender = new BroadcastChannel("px");
      a.onmessage = (e) => { globalThis.ea = e; e.data.data[3] = 1; };
      b.onmessage = (e) => { globalThis.eb = e; e.data.data[3] = 2; };
      sender.postMessage(img);
    JS
    @h.pump
    @h.runtime.collect_garbage
    @h.pump
    assert_equal([9, 1, 9, 2, false], @h.evaluate(<<~JS))
      [ea.data.data[0], ea.data.data[3], eb.data.data[0], eb.data.data[3], ea.data === eb.data]
    JS
  end

  # A clone of an ImageData whose data was never read is transparent black.
  def test_cloning_an_unread_image_data
    assert_equal([24, 0], @h.evaluate(<<~JS))
      (() => {
        const fresh = structuredClone(ctx.createImageData(2, 3));
        return [fresh.data.length, fresh.data.reduce((a, b) => a + b, 0)];
      })()
    JS
  end
end
