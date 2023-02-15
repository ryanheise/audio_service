package com.ryanheise.audioservice;

import java.util.Map;
import java.util.Objects;

public class CustomAction {
    public final String name;
    public final Map<?, ?> extras;

    public CustomAction(String name, Map<?, ?> extras) {
        this.name = name;
        this.extras = extras;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        CustomAction that = (CustomAction) o;
        return name.equals(that.name) && Objects.equals(extras, that.extras);
    }

    @Override
    public int hashCode() {
        return Objects.hash(name, extras);
    }
}
