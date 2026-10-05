({
    // Nothing is written from this modal, so closing it must not save anything.
    unrender: function (component) {
        this.superUnrender();
    }
})