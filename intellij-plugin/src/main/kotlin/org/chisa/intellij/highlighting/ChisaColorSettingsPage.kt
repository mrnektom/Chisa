package org.chisa.intellij.highlighting

import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.openapi.fileTypes.SyntaxHighlighter
import com.intellij.openapi.options.colors.AttributesDescriptor
import com.intellij.openapi.options.colors.ColorDescriptor
import com.intellij.openapi.options.colors.ColorSettingsPage
import javax.swing.Icon

class ChisaColorSettingsPage : ColorSettingsPage {

    companion object {
        private val DESCRIPTORS = arrayOf(
            AttributesDescriptor("Keyword", ChisaSyntaxHighlighter.KEYWORD),
            AttributesDescriptor("Number", ChisaSyntaxHighlighter.NUMBER),
            AttributesDescriptor("String", ChisaSyntaxHighlighter.STRING),
            AttributesDescriptor("Line comment", ChisaSyntaxHighlighter.LINE_COMMENT),
            AttributesDescriptor("Operator", ChisaSyntaxHighlighter.OPERATION_SIGN),
            AttributesDescriptor("Parentheses", ChisaSyntaxHighlighter.PARENTHESES),
            AttributesDescriptor("Braces", ChisaSyntaxHighlighter.BRACES),
            AttributesDescriptor("Brackets", ChisaSyntaxHighlighter.BRACKETS),
            AttributesDescriptor("Comma", ChisaSyntaxHighlighter.COMMA),
            AttributesDescriptor("Semicolon", ChisaSyntaxHighlighter.SEMICOLON),
            AttributesDescriptor("Identifier", ChisaSyntaxHighlighter.IDENTIFIER),
            AttributesDescriptor("Function declaration", ChisaSyntaxHighlighter.FUNCTION_NAME),
            AttributesDescriptor("Function call", ChisaSyntaxHighlighter.FUNCTION_CALL),
            AttributesDescriptor("Field", ChisaSyntaxHighlighter.FIELD_NAME),
            AttributesDescriptor("Enum variant", ChisaSyntaxHighlighter.ENUM_VARIANT_NAME),
            AttributesDescriptor("Bad character", ChisaSyntaxHighlighter.BAD_CHARACTER),
        )

        private val ADDITIONAL_HIGHLIGHTING_TAG_TO_DESCRIPTOR_MAP = mapOf(
            "fnDecl" to ChisaSyntaxHighlighter.FUNCTION_NAME,
            "fnCall" to ChisaSyntaxHighlighter.FUNCTION_CALL,
            "field" to ChisaSyntaxHighlighter.FIELD_NAME,
            "enumVariant" to ChisaSyntaxHighlighter.ENUM_VARIANT_NAME,
        )
    }

    override fun getIcon(): Icon? = null

    override fun getHighlighter(): SyntaxHighlighter = ChisaSyntaxHighlighter()

    override fun getDemoText(): String = """
        // Chisa example
        struct Point { <field>x</field>: number, <field>y</field>: number }

        type Predicate<T> = (T) -> boolean

        fn <fnDecl>distance</fnDecl>(p: Point): number = <fnCall>sqrt</fnCall>(p.<field>x</field> * p.<field>x</field> + p.<field>y</field> * p.<field>y</field>)

        fn Point.<fnDecl>scale</fnDecl>(factor: number): Point = Point { x: this.<field>x</field> * factor, y: this.<field>y</field> * factor }

        fn <fnDecl>main</fnDecl>() {
            let p = Point { x: 3, y: 4 }
            let d = <fnCall>distance</fnCall>(p)
            let doubled = p?.scale(2)!!
            let transform: (number) -> number = { x -> x * 2 }
            when {
                os == "linux" -> <fnCall>print</fnCall>(d),
                else -> <fnCall>print</fnCall>(0)
            }
        }

        enum Color { <enumVariant>Red</enumVariant>, <enumVariant>Green</enumVariant>, <enumVariant>Blue</enumVariant> }
    """.trimIndent()

    override fun getAdditionalHighlightingTagToDescriptorMap(): Map<String, TextAttributesKey> =
        ADDITIONAL_HIGHLIGHTING_TAG_TO_DESCRIPTOR_MAP

    override fun getAttributeDescriptors(): Array<AttributesDescriptor> = DESCRIPTORS

    override fun getColorDescriptors(): Array<ColorDescriptor> = ColorDescriptor.EMPTY_ARRAY

    override fun getDisplayName(): String = "Chisa"
}
