defmodule Fuse.EventStream.SSETest do
  use ExUnit.Case, async: true

  alias Fuse.EventStream.SSE

  describe "parse/1 — single complete events" do
    test "extracts the data payload from an id + data frame" do
      assert {[~s({"state":"running"})], ""} =
               SSE.parse(~s(id: abc123\ndata: {"state":"running"}\n\n))
    end

    test "strips the single optional leading space after data:" do
      assert {["payload"], ""} = SSE.parse("data: payload\n\n")
      assert {["payload"], ""} = SSE.parse("data:payload\n\n")
    end

    test "preserves further spaces in the payload" do
      assert {["  two leading"], ""} = SSE.parse("data:   two leading\n\n")
    end
  end

  describe "parse/1 — multiple frames in one chunk" do
    test "returns all complete payloads in order" do
      chunk = "data: a\n\ndata: b\n\ndata: c\n\n"
      assert {["a", "b", "c"], ""} = SSE.parse(chunk)
    end
  end

  describe "parse/1 — partial frames carry over" do
    test "an incomplete trailing frame is returned as rest" do
      assert {["a"], "data: b"} = SSE.parse("data: a\n\ndata: b")
    end

    test "a frame split mid-way across two chunks reassembles" do
      {events1, rest1} = SSE.parse(~s(data: {"sta))
      assert events1 == []
      assert rest1 == ~s(data: {"sta)

      {events2, rest2} = SSE.parse(rest1 <> ~s(te":"running"}\n\n))
      assert events2 == [~s({"state":"running"})]
      assert rest2 == ""
    end

    test "a split exactly on the blank-line boundary reassembles" do
      {e1, rest1} = SSE.parse("data: a\n")
      assert e1 == []
      {e2, rest2} = SSE.parse(rest1 <> "\ndata: b\n\n")
      assert e2 == ["a", "b"]
      assert rest2 == ""
    end
  end

  describe "parse/1 — comments and keepalives" do
    test "a lone keepalive comment frame yields nothing" do
      assert {[], ""} = SSE.parse(": keepalive\n\n")
    end

    test "keepalives interleaved with events are dropped" do
      chunk = "data: a\n\n: keepalive\n\ndata: b\n\n"
      assert {["a", "b"], ""} = SSE.parse(chunk)
    end
  end

  describe "parse/1 — non-data fields and multi-line data" do
    test "ignores id:, event: and unknown fields" do
      frame = "id: 1\nevent: state\nretry: 3000\ndata: payload\n\n"
      assert {["payload"], ""} = SSE.parse(frame)
    end

    test "joins multiple data: lines with a newline (SSE spec)" do
      assert {["line1\nline2"], ""} = SSE.parse("data: line1\ndata: line2\n\n")
    end

    test "tolerates CRLF line endings" do
      assert {["payload"], ""} = SSE.parse("id: 1\r\ndata: payload\r\n\r\n")
    end
  end

  describe "parse/1 — edge cases" do
    test "empty buffer yields no events and empty rest" do
      assert {[], ""} = SSE.parse("")
    end

    test "buffer with no terminator is all leftover" do
      assert {[], "data: a"} = SSE.parse("data: a")
    end
  end
end
