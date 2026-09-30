"""
Phase Y: Warehouse Inbound Unit Barcode Labels PDF Generator.

Built with reportlab to generate high-resolution, vector Code128 scannable barcodes
for each unit in an accepted WarehouseInboundRequest. Reused across both warehouse
staff and seller portal for unit identification, box labelling, and scan verification.

Supports multiple paper formats:
- 'a4': Standard A4 multi-label sheet in a clean 2-column grid.
- 'thermal_4x6': Standard 4x6 inch thermal roll (1 label per page).
- 'thermal_2x1': Compact 2x1 inch thermal barcode sticker roll (1 label per page).
"""
import io
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, inch
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.graphics.barcode.code128 import Code128

INK = colors.HexColor("#0f172a")
MUTED = colors.HexColor("#64748b")
BORDER = colors.HexColor("#cbd5e1")
BG_HEADER = colors.HexColor("#f8fafc")
PRIMARY = colors.HexColor("#2563eb")


def _render_a4_grid(inbound_req, units) -> bytes:
    """Renders multi-unit labels on standard A4 paper in a 2-column grid."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=10 * mm,
        rightMargin=10 * mm,
        topMargin=10 * mm,
        bottomMargin=10 * mm,
        title=f"Inbound Labels #{inbound_req.id} - {inbound_req.product.sku}",
        author="SEVO Logistics",
    )

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "A4TitleStyle", parent=styles["Normal"], fontSize=12, leading=16, fontName="Helvetica-Bold", textColor=INK
    )
    label_unit = ParagraphStyle(
        "A4LabelUnit", parent=styles["Normal"], fontSize=8, leading=10, fontName="Helvetica-Bold", textColor=PRIMARY
    )
    label_meta_right = ParagraphStyle(
        "A4LabelMetaRight", parent=styles["Normal"], fontSize=7, leading=9, fontName="Helvetica-Bold", textColor=MUTED, alignment=2
    )
    label_title = ParagraphStyle(
        "A4LabelTitle", parent=styles["Normal"], fontSize=8, leading=10, fontName="Helvetica-Bold", textColor=INK
    )
    label_sku = ParagraphStyle(
        "A4LabelSku", parent=styles["Normal"], fontSize=7, leading=9, fontName="Helvetica", textColor=MUTED
    )

    story = []

    company_name = getattr(inbound_req.company, "company_name", None) or getattr(inbound_req.company, "name", "")
    warehouse_name = inbound_req.warehouse.name
    product_title = inbound_req.product.title
    sku = inbound_req.product.sku

    header_text = (
        f"<b>SEVO WAREHOUSE INBOUND UNIT LABELS</b><br/>"
        f"<font size=8.5 color='#64748b'>Request #{inbound_req.id} &bull; Warehouse: <b>{warehouse_name}</b> &bull; Seller: <b>{company_name}</b></font><br/>"
        f"<font size=8.5 color='#64748b'>Product: <b>{product_title}</b> &bull; SKU: <font color='#0f172a'><b>{sku}</b></font> &bull; Total Units: <b>{inbound_req.requested_quantity}</b></font>"
    )

    header_table = Table([[Paragraph(header_text, title_style)]], colWidths=[190 * mm])
    header_table.setStyle(
        TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), BG_HEADER),
            ("BOX", (0, 0), (-1, -1), 0.75, BORDER),
            ("TOPPADDING", (0, 0), (-1, -1), 3.5 * mm),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5 * mm),
            ("LEFTPADDING", (0, 0), (-1, -1), 4 * mm),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4 * mm),
        ])
    )
    story.append(header_table)
    story.append(Spacer(1, 5 * mm))

    table_data = []
    row_cells = []

    for unit in units:
        barcode_flowable = Code128(
            unit.barcode,
            barHeight=12 * mm,
            barWidth=0.72,
            humanReadable=True,
            fontSize=7,
            fontName="Courier-Bold",
            quiet=True,
        )
        barcode_flowable.hAlign = "CENTER"

        unit_badge = f"Unit {unit.unit_number} of {inbound_req.requested_quantity}"
        truncated_title = (product_title[:28] + "...") if len(product_title) > 30 else product_title

        card_header = Table(
            [[Paragraph(f"<b>{unit_badge}</b>", label_unit), Paragraph(f"Req #{inbound_req.id}", label_meta_right)]],
            colWidths=[55 * mm, 29 * mm],
        )
        card_header.setStyle(
            TableStyle([
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ])
        )

        cell_content = [
            card_header,
            Spacer(1, 1 * mm),
            Paragraph(f"{truncated_title}", label_title),
            Paragraph(f"SKU: <b>{sku}</b>", label_sku),
            Spacer(1, 1.5 * mm),
            barcode_flowable,
        ]

        card_table = Table([[item] for item in cell_content], colWidths=[84 * mm])
        card_table.setStyle(
            TableStyle([
                ("BOX", (0, 0), (-1, -1), 0.75, BORDER),
                ("BACKGROUND", (0, 0), (-1, -1), colors.white),
                ("TOPPADDING", (0, 0), (-1, -1), 2.5 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5 * mm),
                ("LEFTPADDING", (0, 0), (-1, -1), 3.5 * mm),
                ("RIGHTPADDING", (0, 0), (-1, -1), 3.5 * mm),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
            ])
        )

        row_cells.append(card_table)
        if len(row_cells) == 2:
            table_data.append(row_cells)
            row_cells = []

    if row_cells:
        row_cells.append("")
        table_data.append(row_cells)

    if table_data:
        grid_table = Table(table_data, colWidths=[95 * mm, 95 * mm])
        grid_table.setStyle(
            TableStyle([
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5 * mm),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ])
        )
        story.append(grid_table)

    doc.build(story)
    return buffer.getvalue()


def _render_thermal_4x6(inbound_req, units) -> bytes:
    """Renders 1 label per page on a 4x6 inch thermal label roll."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=(4 * inch, 6 * inch),
        leftMargin=6 * mm,
        rightMargin=6 * mm,
        topMargin=6 * mm,
        bottomMargin=6 * mm,
        title=f"Inbound Labels 4x6 #{inbound_req.id} - {inbound_req.product.sku}",
        author="SEVO Logistics",
    )

    styles = getSampleStyleSheet()
    brand_style = ParagraphStyle(
        "T4Brand", parent=styles["Normal"], fontSize=11, leading=14, fontName="Helvetica-Bold", textColor=INK
    )
    sub_style = ParagraphStyle(
        "T4Sub", parent=styles["Normal"], fontSize=8, leading=10, fontName="Helvetica", textColor=MUTED
    )
    unit_badge_style = ParagraphStyle(
        "T4UnitBadge", parent=styles["Normal"], fontSize=13, leading=16, fontName="Helvetica-Bold", textColor=PRIMARY, alignment=1
    )
    prod_title_style = ParagraphStyle(
        "T4ProdTitle", parent=styles["Normal"], fontSize=11, leading=14, fontName="Helvetica-Bold", textColor=INK
    )
    sku_style = ParagraphStyle(
        "T4Sku", parent=styles["Normal"], fontSize=9, leading=12, fontName="Helvetica-Bold", textColor=INK
    )
    meta_style = ParagraphStyle(
        "T4Meta", parent=styles["Normal"], fontSize=7.5, leading=10, fontName="Helvetica", textColor=MUTED
    )

    story = []
    company_name = getattr(inbound_req.company, "company_name", None) or getattr(inbound_req.company, "name", "")
    warehouse_name = inbound_req.warehouse.name
    product_title = inbound_req.product.title
    sku = inbound_req.product.sku

    content_w = (4 * inch) - 12 * mm

    for idx, unit in enumerate(units):
        card_elements = []

        top_hdr = Table([
            [
                Paragraph("<b>SEVO LOGISTICS</b>", brand_style),
                Paragraph(f"Req #{inbound_req.id}", ParagraphStyle("T4R", parent=sub_style, alignment=2, fontName="Helvetica-Bold"))
            ],
            [
                Paragraph(f"Warehouse: <b>{warehouse_name}</b>", sub_style),
                Paragraph(f"Seller: <b>{company_name}</b>", ParagraphStyle("T4R2", parent=sub_style, alignment=2))
            ]
        ], colWidths=[content_w * 0.55, content_w * 0.45])
        top_hdr.setStyle(
            TableStyle([
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1 * mm),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("LINEBELOW", (0, 1), (-1, 1), 0.75, BORDER),
            ])
        )
        card_elements.append(top_hdr)
        card_elements.append(Spacer(1, 3 * mm))

        unit_text = f"UNIT {unit.unit_number} OF {inbound_req.requested_quantity}"
        unit_table = Table([[Paragraph(f"<b>{unit_text}</b>", unit_badge_style)]], colWidths=[content_w])
        unit_table.setStyle(
            TableStyle([
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#eff6ff")),
                ("BOX", (0, 0), (-1, -1), 0.75, colors.HexColor("#bfdbfe")),
                ("TOPPADDING", (0, 0), (-1, -1), 2.5 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5 * mm),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
            ])
        )
        card_elements.append(unit_table)
        card_elements.append(Spacer(1, 3 * mm))

        card_elements.append(Paragraph(f"{product_title}", prod_title_style))
        card_elements.append(Spacer(1, 1.5 * mm))
        card_elements.append(Paragraph(f"SKU: <font color='#2563eb'>{sku}</font>", sku_style))
        card_elements.append(Spacer(1, 3.5 * mm))

        barcode_flowable = Code128(
            unit.barcode,
            barHeight=22 * mm,
            barWidth=1.0,
            humanReadable=True,
            fontSize=9,
            fontName="Courier-Bold",
            quiet=True,
        )
        barcode_flowable.hAlign = "CENTER"

        barcode_box = Table([[barcode_flowable]], colWidths=[content_w])
        barcode_box.setStyle(
            TableStyle([
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 2 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2 * mm),
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f8fafc")),
                ("BOX", (0, 0), (-1, -1), 0.5, BORDER),
            ])
        )
        card_elements.append(barcode_box)
        card_elements.append(Spacer(1, 3 * mm))

        footer_p = Paragraph(
            "Affix this label securely to incoming unit. Scannable verification at intake check-in.",
            meta_style,
        )
        card_elements.append(footer_p)

        story.extend(card_elements)
        if idx < len(units) - 1:
            story.append(PageBreak())

    doc.build(story)
    return buffer.getvalue()


def _render_thermal_2x1(inbound_req, units) -> bytes:
    """Renders 1 label per page on a 2x1 inch compact thermal sticker roll."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=(2 * inch, 1 * inch),
        leftMargin=2 * mm,
        rightMargin=2 * mm,
        topMargin=1.5 * mm,
        bottomMargin=1.5 * mm,
        title=f"Inbound Labels 2x1 #{inbound_req.id} - {inbound_req.product.sku}",
        author="SEVO Logistics",
    )

    styles = getSampleStyleSheet()
    hdr_left = ParagraphStyle(
        "T2HdrL", parent=styles["Normal"], fontSize=5.5, leading=7, fontName="Helvetica-Bold", textColor=PRIMARY
    )
    hdr_right = ParagraphStyle(
        "T2HdrR", parent=styles["Normal"], fontSize=5.5, leading=7, fontName="Helvetica-Bold", textColor=MUTED, alignment=2
    )
    sku_style = ParagraphStyle(
        "T2Sku", parent=styles["Normal"], fontSize=6, leading=7.5, fontName="Helvetica-Bold", textColor=INK
    )

    story = []
    content_w = (2 * inch) - 4 * mm

    for idx, unit in enumerate(units):
        card_elements = []

        hdr_tbl = Table([
            [
                Paragraph(f"<b>Unit {unit.unit_number}/{inbound_req.requested_quantity}</b>", hdr_left),
                Paragraph(f"Req #{inbound_req.id}", hdr_right),
            ],
        ], colWidths=[content_w * 0.6, content_w * 0.4])
        hdr_tbl.setStyle(
            TableStyle([
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ])
        )
        card_elements.append(hdr_tbl)

        truncated_sku = inbound_req.product.sku[:18]
        card_elements.append(Paragraph(f"{truncated_sku}", sku_style))

        barcode_flowable = Code128(
            unit.barcode,
            barHeight=7.5 * mm,
            barWidth=0.52,
            humanReadable=True,
            fontSize=4.5,
            fontName="Courier-Bold",
            quiet=True,
        )
        barcode_flowable.hAlign = "CENTER"
        card_elements.append(barcode_flowable)

        story.extend(card_elements)
        if idx < len(units) - 1:
            story.append(PageBreak())

    doc.build(story)
    return buffer.getvalue()


def render_inbound_unit_labels_pdf(inbound_req, paper_size="a4") -> bytes:
    """
    Renders printable barcode labels for an accepted WarehouseInboundRequest.
    Formats units according to the requested paper size:
    - 'a4': Multi-label grid on A4 sheet.
    - 'thermal_4x6' / '4x6': Single label per page for standard thermal printers.
    - 'thermal_2x1' / '2x1': Single label per page for compact 2x1 sticker printers.
    """
    units = list(inbound_req.units.all().order_by("unit_number"))
    normalized = (paper_size or "a4").strip().lower()

    if normalized in ("thermal_4x6", "4x6", "4_6"):
        return _render_thermal_4x6(inbound_req, units)
    elif normalized in ("thermal_2x1", "2x1", "2_1"):
        return _render_thermal_2x1(inbound_req, units)
    else:
        return _render_a4_grid(inbound_req, units)
